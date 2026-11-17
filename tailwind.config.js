/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      fontFamily: { sans: ['Lato', 'system-ui', 'sans-serif'] },
      colors: {
        brand: { 50: '#EEF6F4', 100: '#D5E9E4', 200: '#A9D2C8', 300: '#74B4A5', 400: '#3F8E7E', 500: '#2A7566', 600: '#1F5C52', 700: '#184A42', 800: '#123A34', 900: '#0C2925' },
        accent: { 100: '#FAF6D5', 300: '#EFE38A', 400: '#E2D54B', 500: '#CDBE2E', 600: '#A99B1F' },
      },
    },
  },
  plugins: [],
}
