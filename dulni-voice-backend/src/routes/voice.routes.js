
import express from 'express';
import { generateSpeech } from '../services/humain.service.js';

const router = express.Router();

router.post('/tts', async (req, res) => {
  try {
    const { text, voicePersona = 'sara' } = req.body;

    // Validate text
    if (
      typeof text !== 'string' ||
      !text.trim() ||
      text.length > 1000
    ) {
      return res.status(400).json({
        success: false,
        message: 'Text must contain 1-1000 characters.',
      });
    }

    // Validate voice persona
    if (!['sara', 'abdulaziz'].includes(voicePersona)) {
      return res.status(400).json({
        success: false,
        message: 'Unsupported voice persona.',
      });
    }

    const audio = await generateSpeech(text, voicePersona);

    res.set({
      'Content-Type': 'audio/wav',
      'Content-Length': audio.length,
      'Content-Disposition': 'inline; filename="dulni-speech.wav"',
    });

    return res.status(200).send(audio);

  } catch (error) {
    console.error('TTS endpoint error:', error);

    return res.status(500).json({
      success: false,
      message: 'Unable to generate speech.',
    });
  }
});

export default router;
