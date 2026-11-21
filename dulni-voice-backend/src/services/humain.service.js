
import {
  TTSClient,
  TtsModel,
  getSampleRate,
} from '@humain-voice/sdk';

const VOICES = {
  sara: () => process.env.TTS_SARA_VOICE_ID,
  abdulaziz: () => process.env.TTS_ABDULAZIZ_VOICE_ID,
};

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

export async function generateSpeech(text, voicePersona = 'sara') {
  const voiceId = VOICES[voicePersona]?.();

  if (!voiceId) {
    throw new Error('Voice configuration is missing');
  }

  if (!process.env.API_KEY || !process.env.API_URL) {
    throw new Error('HUMAIN configuration is missing');
  }

  const client = new TTSClient({
    api_url: process.env.API_URL,
    api_key: process.env.API_KEY,
  });

  try {
    const model = TtsModel.Nebula;

    const pcm = await client.synthesize(text, {
      voice_id: voiceId,
      model,
      timeoutSeconds: 30,
      onError: (error) => {
        console.error('HUMAIN TTS error:', error.code, error.message);
      },
    });

    return pcm16ToWav(pcm, getSampleRate(model));
  } finally {
    await client.close();
  }
}
