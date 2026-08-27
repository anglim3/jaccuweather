const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { execSync } = require('child_process');

try {
  if (fs.existsSync(path.join(__dirname, 'convert-favicon.js'))) {
    execSync('node convert-favicon.js', { stdio: 'inherit' });
  }
} catch (error) {
  console.warn('Warning: Could not convert favicon to PNG:', error.message);
  console.warn('Continuing with build...');
}

let htmlContent = fs.readFileSync(path.join(__dirname, 'public', 'index.html'), 'utf8');
const jsContent = fs.readFileSync(path.join(__dirname, 'public', 'app.js'), 'utf8');
const faviconContent = fs.readFileSync(path.join(__dirname, 'public', 'favicon.svg'), 'utf8');
const appleTouchIconContent = fs.readFileSync(path.join(__dirname, 'public', 'apple-touch-icon.png'));
const svgHash = crypto.createHash('md5').update(faviconContent).digest('hex').substring(0, 8);
htmlContent = htmlContent.replace(/href="\/apple-touch-icon\.png"/, `href="/apple-touch-icon.png?v=${svgHash}`);
const appleTouchIconBase64 = appleTouchIconContent.toString('base64');
const workerContent = fs.readFileSync(path.join(__dirname, 'worker-template.js'), 'utf8')
  .replace('__HTML_CONTENT__', JSON.stringify(htmlContent))
  .replace('__JS_CONTENT__', JSON.stringify(jsContent))
  .replace('__FAVICON_CONTENT__', JSON.stringify(faviconContent))
  .replace('__APPLE_TOUCH_ICON_BASE64__', JSON.stringify(appleTouchIconBase64));
fs.writeFileSync(path.join(__dirname, 'src', 'index.js'), workerContent);
console.log('Build complete! Generated src/index.js');
