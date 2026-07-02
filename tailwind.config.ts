import type { Config } from 'tailwindcss';

const config: Config = {
  content: ['./app/**/*.{ts,tsx}', './components/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        brand: {
          50: '#f5f7ff',
          100: '#ebf0fe',
          500: '#3b5bdb',
          600: '#364fc7',
          700: '#2f44ad',
        },
      },
    },
  },
  plugins: [],
};

export default config;
