
import express from 'express';
import rateLimit from 'express-rate-limit';
import { appCheck } from '../config/firebase-admin.js';
import { generateSpeech } from '../services/humain.service.js';

const router = express.Router();

// Verify Firebase App Check token
const requireAppCheck = async (req, res, next) => {
  const appCheckToken = req.get('X-Firebase-AppCheck');

  if (!appCheckToken) {
    return res.status(401).json({
      success: false,
      message: 'App verification required.',
    });
  }

  try {
    await appCheck.verifyToken(appCheckToken);
    return next();
  } catch {
    return res.status(401).json({
      success: false,
      message: 'Invalid or expired app verification token.',
    });
  }
};

// Limit Azure STT token requests
const sttTokenLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 10,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many token requests. Please try again later.',
  },
});

// Limit HUMAIN TTS requests
const ttsLimiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many speech requests. Please try again later.',
  },
});

// Azure Speech authorization token
router.post(
  '/stt-token',
  sttTokenLimiter,
  requireAppCheck,
  async (req, res) => {
    try {
      const speechKey = process.env.AZURE_SPEECH_KEY;
      const region = process.env.AZURE_SPEECH_REGION;

      if (!speechKey || !region) {
        return res.status(500).json({
          success: false,
          message: 'Azure Speech configuration is missing.',
        });
      }

      const azureResponse = await fetch(
        `https://${region}.api.cognitive.microsoft.com/sts/v1.0/issueToken`,
        {
          method: 'POST',
          headers: {
            'Ocp-Apim-Subscription-Key': speechKey,
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: '',
          signal: AbortSignal.timeout(10000),
        }
      );

      if (!azureResponse.ok) {
        console.error(
          'Azure STT token request failed:',
          azureResponse.status
        );

        return res.status(502).json({
          success: false,
          message: 'Unable to obtain Azure Speech token.',
        });
      }

      const token = (await azureResponse.text()).trim();

      if (!token) {
        return res.status(502).json({
          success: false,
          message: 'Azure returned an empty token.',
        });
      }

      return res.status(200).json({
        success: true,
        token,
        region,
        expiresInSeconds: 600,
      });
    } catch (error) {
      console.error('Azure STT token endpoint error:', error.message);

      return res.status(502).json({
        success: false,
        message: 'Unable to obtain Azure Speech token.',
      });
    }
  }
);

// HUMAIN TTS endpoint
router.post('/tts', ttsLimiter, requireAppCheck, async (req, res) => {
  try {
    const { text, voicePersona = 'sara' } = req.body;

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
