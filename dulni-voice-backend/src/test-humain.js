
import dotenv from 'dotenv';
import { TTSClient } from '@humain-voice/sdk';

dotenv.config();

async function testHumain() {
  if (!process.env.API_KEY || !process.env.API_URL) {
    throw new Error('Missing HUMAIN environment variables');
  }

  const client = new TTSClient({
    api_url: process.env.API_URL,
    api_key: process.env.API_KEY,
  });

  try {
    console.log('Connecting to HUMAIN Voice...');

    const voices = await client.listVoices({
      timeoutSeconds: 10,
    });

    console.log('\nAvailable voices:');

    for (const voice of voices) {
      console.log({
        id: voice.id,
        label: voice.label,
        dialect: voice.profile?.speaker?.dialect,
        languages: voice.profile?.languages,
      });
    }

    if (voices.length === 0) {
      console.log('No voices available for this environment.');
    }
  } finally {
    await client.close();
  }
}

testHumain().catch((error) => {
  console.error('HUMAIN test failed:', error);
  process.exit(1);
});
