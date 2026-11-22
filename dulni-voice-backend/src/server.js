
import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import voiceRoutes from './routes/voice.routes.js';
import authRoutes from './routes/auth.routes.js';

dotenv.config();

const app = express();

app.use(cors());
app.use(express.json({ limit: '1mb' }));

app.get('/health', (req, res) => {
  res.status(200).json({
    success: true,
    message: 'Dulni Voice Backend is running',
  });
});

app.use('/api/voice', voiceRoutes);
app.use('/api/auth', authRoutes);

const PORT = process.env.PORT || 3000;

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Dulni Backend running on port ${PORT}`);
});

app.use((req, res, next) => {
  console.log(`Incoming request: ${req.method} ${req.path}`);
  next();
});