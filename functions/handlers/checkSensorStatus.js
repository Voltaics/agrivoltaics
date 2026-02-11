const functions = require('firebase-functions');
const {Timestamp} = require('firebase-admin/firestore');
const {db} = require('../lib/firebase');

/**
 * Scheduled Cloud Function: Check Sensor Status
 */
const checkSensorStatus = functions.pubsub
    .schedule('every 24 hours')
    .onRun(async () => {
      const thirtyMinutesAgo = Timestamp.fromMillis(Date.now() - 30 * 60 * 1000);

      try {
        const lookupSnapshot = await db.collection('sensorLookup')
            .where('isActive', '==', true)
            .where('lastDataReceived', '<', thirtyMinutesAgo)
            .get();

        const batch = db.batch();
        let updateCount = 0;

        for (const doc of lookupSnapshot.docs) {
          const data = doc.data();
          const sensorRef = db.doc(data.sensorDocPath);

          batch.update(sensorRef, {
            isOnline: false,
          });

          updateCount++;

          if (updateCount >= 500) {
            await batch.commit();
            updateCount = 0;
          }
        }

        if (updateCount > 0) {
          await batch.commit();
        }

        console.log(`Marked ${lookupSnapshot.size} sensors as offline`);
      } catch (error) {
        console.error('Error checking sensor status:', error);
      }
    });
module.exports = {checkSensorStatus};
