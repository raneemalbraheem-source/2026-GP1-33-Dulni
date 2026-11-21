import express from 'express';
import rateLimit from 'express-rate-limit';
import { auth } from '../config/firebase-admin.js';

const router = express.Router();

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 5,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: {
    success: false,
    message: 'Too many requests. Please try again later.',
  },
});

router.post('/check-email', authLimiter, async (req, res) => {
  try {
    const { email } = req.body;

    if (
      typeof email !== 'string' ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())
    ) {
      return res.status(400).json({
        success: false,
        message: 'Please provide a valid email address.',
      });
    }

    let canSendLink = false;

    try {
      await auth.getUserByEmail(email.trim().toLowerCase());
      canSendLink = true;
    } catch (error) {
      if (error.code !== 'auth/user-not-found') {
        throw error;
      }
    }

    return res.status(200).json({
      success: true,
      canSendLink,
      message:
        'If an account exists, a sign-in link will be sent to your email.',
    });
  } catch (error) {
    console.error('Email check endpoint failed:', error.code || 'unknown');

    return res.status(500).json({
      success: false,
      message: 'Unable to process your request.',
    });
  }
});

export default router;