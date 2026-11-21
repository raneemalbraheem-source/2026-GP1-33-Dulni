
import dotenv from 'dotenv';
import { writeFile } from 'node:fs/promises';
import {
  TTSClient,
  TtsModel,
  getSampleRate,
} from '@humain-voice/sdk';

dotenv.config();

function pcm16ToWav(pcm, sampleRate) {
  const header = Buffer.alloc(44);

  header.write('RIFF', 0);
  header.writeUInt32LE(36 + pcm.byteLength, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(pcm.byteLength, 40);

  return Buffer.concat([header, Buffer.from(pcm)]);
}

async function main() {
  const text = 'مرحباً بك في دُلّني، كيف يمكنني مساعدتك اليوم؟';

  const voiceId = process.env.TTS_VOICE_ID;

  if (!process.env.API_KEY || !process.env.API_URL || !voiceId) {
    throw new Error('Missing API_KEY, API_URL, or TTS_VOICE_ID');
  }

  const client = new TTSClient({
    api_url: process.env.API_URL,
    api_key: process.env.API_KEY,
  });

  try {
    console.log('Generating Arabic speech...');

    const pcm = await client.synthesize(text, {
      voice_id: voiceId,
      model: TtsModel.Nebula,
      timeoutSeconds: 30,
      onError: (error) => {
        console.error('HUMAIN error:', error.code, error.message);
      },
    });

    const wav = pcm16ToWav(pcm, getSampleRate(TtsModel.Nebula));

    await writeFile('dulni-test.wav', wav);

    console.log('Success! Audio saved as dulni-test.wav');
    console.log('Audio size:', wav.length, 'bytes');
  } finally {
    await client.close();
  }
}

main().catch((error) => {
  console.error('TTS failed:', error);
  process.exitCode = 1;
});
