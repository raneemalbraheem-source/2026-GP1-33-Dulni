
import { getApps, initializeApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';
import { getAppCheck } from 'firebase-admin/app-check';

import serviceAccount from '../../secrets/dulni-service-account.json' with { type: 'json' };

const app = getApps().length
  ? getApps()[0]
  : initializeApp({
      credential: cert(serviceAccount),
    });

export const auth = getAuth(app);
export const db = getFirestore(app);
export const appCheck = getAppCheck(app);