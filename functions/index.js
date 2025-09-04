// functions/index.js — Firebase Functions v2 (Node.js 22 / Gen 2)

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const logger = require('firebase-functions/logger');

const { initializeApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');

initializeApp();
const db = getFirestore();
const auth = getAuth();

// ===============================
// testAuth (callable, public)
// ===============================
exports.testAuth = onCall(
  { region: 'us-central1', invoker: 'public' },
  async (request) => {
    logger.info('Test function called');

    if (!request.auth) {
      logger.warn('No auth in request');
      throw new HttpsError('unauthenticated', 'No authentication found');
    }

    logger.info('Auth found', { uid: request.auth.uid });

    return {
      success: true,
      authUid: request.auth.uid,
      message: 'Authentication working correctly',
    };
  }
);

// ===============================
// adminDeleteUser (callable, public)
// ===============================
exports.adminDeleteUser = onCall(
  { region: 'us-central1', invoker: 'public' },
  async (request) => {
    logger.info('Admin delete function called');

    // 1) Auth requise
    if (!request.auth) {
      logger.warn('No auth request found');
      throw new HttpsError('unauthenticated', 'User must be authenticated');
    }
    const callerUid = request.auth.uid;
    logger.info('Authenticated user ID', { uid: callerUid });

    // 2) Vérif rôle admin
    const callerDoc = await db.collection('users').doc(callerUid).get();
    if (!callerDoc.exists) {
      logger.warn('User profile not found', { uid: callerUid });
      throw new HttpsError('permission-denied', 'User profile not found');
    }
    const userData = callerDoc.data();
    if (userData?.role !== 'admin') {
      logger.warn('User is not admin', { uid: callerUid, role: userData?.role });
      throw new HttpsError('permission-denied', 'Admin access required');
    }

    // 3) Paramètres
    const { userId } = request.data || {};
    if (!userId) throw new HttpsError('invalid-argument', 'userId is required');
    if (callerUid === userId) {
      throw new HttpsError('invalid-argument', 'Cannot delete your own admin account');
    }
    logger.info('Attempting to delete user', { userId });

    // Helpers
    const collectRefs = async (query) => {
      const snap = await query.get();
      return snap.docs.map((d) => d.ref);
    };
    const commitInChunks = async (refs, chunkSize = 450) => {
      for (let i = 0; i < refs.length; i += chunkSize) {
        const batch = db.batch();
        refs.slice(i, i + chunkSize).forEach((ref) => batch.delete(ref));
        await batch.commit();
      }
    };

    try {
      // 4) Supprimer du Auth
      await auth.deleteUser(userId);
      logger.info('User deleted from Auth', { userId });

      // 5) Récupérer tous les docs à supprimer
      const userRef = db.collection('users').doc(userId);

      const studentBookingRefs = await collectRefs(
        db.collection('booking_requests').where('studentId', '==', userId)
      );
      const ownerBookingRefs = await collectRefs(
        db.collection('booking_requests').where('homeownerId', '==', userId)
      );
      const listingRefs = await collectRefs(
        db.collection('listings').where('ownerId', '==', userId)
      );

      const counts = {
        studentBookings: studentBookingRefs.length,
        ownerBookings: ownerBookingRefs.length,
        listings: listingRefs.length,
      };

      // 6) Suppressions Firestore (en chunks)
      await commitInChunks([userRef, ...studentBookingRefs, ...ownerBookingRefs, ...listingRefs]);

      logger.info('Firestore cleanup completed', { userId, ...counts });

      return {
        success: true,
        message: 'User completely deleted',
        deletedItems: { auth: true, user: true, ...counts },
      };
    } catch (error) {
      logger.error('Error deleting user', { error: error?.message || error, userId });
      throw new HttpsError('internal', 'Failed to delete user: ' + (error?.message || String(error)));
    }
  }
);
