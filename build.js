const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

// Convert SVG to PNG for iOS (if convert-favicon.js exists)
try {
  if (fs.existsSync(path.join(__dirname, 'convert-favicon.js'))) {
    execSync('node convert-favicon.js', { stdio: 'inherit' });
  }
} catch (error) {
  console.warn('Warning: Could not convert favicon to PNG:', error.message);
  console.warn('Continuing with build...');
}

// Read the HTML, JS, and favicon files
let htmlContent = fs.readFileSync(path.join(__dirname, 'public', 'index.html'), 'utf8');
const jsContent = fs.readFileSync(path.join(__dirname, 'public', 'app.js'), 'utf8');
const faviconContent = fs.readFileSync(path.join(__dirname, 'public', 'favicon.svg'), 'utf8');
const appleTouchIconContent = fs.readFileSync(path.join(__dirname, 'public', 'apple-touch-icon.png'));

// Generate a hash of the SVG content for cache-busting
// This ensures the icon URL changes automatically when the icon is modified
const svgHash = crypto.createHash('md5').update(faviconContent).digest('hex').substring(0, 8);

// Update the HTML to include the version parameter in the apple-touch-icon URL
htmlContent = htmlContent.replace(
  /href="\/apple-touch-icon\.png"/,
  `href="/apple-touch-icon.png?v=${svgHash}`
);
