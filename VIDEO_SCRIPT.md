# Platform Deployment Video Script
## Total Runtime: ~8-10 minutes

---

## SEGMENT 1: DOCKERFILE SETUP (1-2 minutes)

### Opening
"Welcome! Today I'm walking you through the complete deployment of our Symfony Platform Technology Project on Railway. Let's start with the Dockerfile, which is the blueprint for our Docker container."

### Key Points

**[Show Dockerfile on screen]**

"Our Dockerfile has two main stages:

**Stage 1: Builder Stage**
- We start with PHP 8.3 FPM as our base image
- Install essential dependencies: git, curl, Node.js, npm
- Install PHP extensions for MySQL connectivity: PDO and PDO MySQL
- Install Composer for dependency management
- Copy composer.json and install PHP dependencies
- Copy the entire application code
- Run post-install scripts including importmap installation
- Warm up the cache for production

**Stage 2: Runtime Stage**
- Start fresh with PHP 8.3 FPM base image (keeps it lightweight)
- Install only necessary runtime dependencies: Nginx and curl
- Copy the pre-built application from the builder stage
- Set file permissions for the www-data user
- Configure PHP-FPM to listen on 127.0.0.1:9000
- Copy Nginx configuration files
- Copy the entrypoint.sh script that handles startup tasks
- Set up health checks to monitor container status
- Expose port 80 for HTTP traffic

The two-stage approach is crucial - it reduces the final image size significantly because we don't include build tools in the runtime container."

---

## SEGMENT 2: NGINX CONFIGURATION (1-2 minutes)

### Opening
"Now let's look at how Nginx handles incoming requests and routes them to our PHP-FPM application."

### Key Points

**[Show nginx.conf on screen]**

"The Nginx configuration is critical for our application to work properly.

**Server Block Basics**
- Listen on port 80 (HTTP traffic)
- Document root is /app/public - this is where index.php lives
- We set security headers to protect against XSS and clickjacking attacks

**Static Asset Handling**
- Files in /assets/ are served directly by Nginx with 1-year cache headers
- This speeds up loading since Nginx doesn't need to call PHP-FPM

**Request Routing**
- The key location block is '/' - this uses try_files to route all requests through index.php
- try_files $uri $uri/ /index.php$is_args$args means:
  - First try to serve the file directly
  - Then try as a directory
  - If neither exists, route to index.php with query strings intact

**PHP-FPM Connection**
- This is crucial: fastcgi_pass 127.0.0.1:9000
- Nginx communicates with PHP-FPM on port 9000
- We set proper SCRIPT_FILENAME and PATH_INFO so PHP knows where the application code is
- Timeout settings prevent requests from hanging

**Security**
- We explicitly deny PHP execution in locations other than index.php
- Hidden files (dotfiles) are blocked
- This prevents direct access to sensitive files"

---

## SEGMENT 3: ENVIRONMENT VARIABLE SETUP (1 minute)

### Opening
"Environment variables are how we configure the application differently for development versus production."

### Key Points

**[Show .env file on screen]**

"Our .env file has three main sections:

**Framework Configuration**
- APP_ENV=prod tells Symfony to run in production mode
- APP_DEBUG=0 disables debug mode (critical for security)
- APP_SECRET is used for cryptographic operations

**Routing Configuration**
- DEFAULT_URI points to our production domain: https://platformfinal-production.up.railway.app

**Database Configuration**
- This is where Railway's managed MySQL service connects
- The DATABASE_URL format is: mysql://user:password@host:port/database

**For Railway Specifically**
- Railway automatically injects environment variables for the MySQL service
- MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PASSWORD, MYSQL_DB_NAME are provided by Railway
- Our entrypoint.sh constructs the full DATABASE_URL from these variables at startup time"

---

## SEGMENT 4: DEPLOYMENT PROCESS WALKTHROUGH (2-3 minutes)

### Opening
"Let's walk through what happens from the moment you push code to GitHub until your app is running on Railway."

### Step-by-Step Process

**[Show GitHub repository]**

"Step 1: Push to GitHub
- Developer commits changes to master branch
- 'git push' sends code to the repository"

**[Show Railway Dashboard]**

"Step 2: Railway Detects Changes
- Railway watches the GitHub repository
- When new commits are pushed, Railway automatically triggers a new build

Step 3: Build Process
- Railway reads the Dockerfile
- Executes both build stages
- This takes 2-3 minutes depending on dependency installations

Step 4: Environment Setup
- Railway injects environment variables from your configuration
- MySQL service is already running and ready to connect

Step 5: Container Startup
- The Dockerfile's ENTRYPOINT runs our entrypoint.sh script
- This script does several critical things:
  - Constructs the DATABASE_URL from Railway's MySQL variables
  - Waits for the database to be ready
  - Runs Doctrine migrations to set up/update the schema
  - Sets file permissions (www-data must be able to write to /var/cache)
  - Starts PHP-FPM in the background
  - Starts Nginx in the foreground

Step 6: Health Check
- Railway runs HTTP health checks to the / endpoint
- Once checks pass, the deployment is marked as successful
- Traffic is routed to the new container"

**[Show entrypoint.sh key sections]**

"The entrypoint.sh script is the orchestrator. It:
1. Constructs DATABASE_URL from Railway environment variables
2. Waits up to 30 seconds for MySQL to be ready
3. Runs migrations to ensure schema is current
4. Clears and warms up the cache
5. Starts both PHP-FPM and Nginx

This is why deployments take a bit longer - we're ensuring the database is ready before the app starts serving requests."

---

## SEGMENT 5: FINAL PROOF - DEPLOYMENT VERIFICATION (1-2 minutes)

### Opening
"Now let's verify that everything is working correctly by testing both key endpoints."

### Testing the Deployment

**[Open browser and navigate to https://platformfinal-production.up.railway.app/]**

"Here we are at the home page. Notice:
- ✅ Application Running badge - the container is healthy
- ✅ Database connection is working badge - MySQL connection successful
- The page displays the 'Platform Technology Dashboard' with a successful deployment message"

**[Click on /product or navigate manually]**

"Now let's check the /product endpoint at /product"

**[Show products page]**

"Perfect! The products list page is loading correctly. This proves:
- ✅ The Nginx routing is working
- ✅ The ProductController is accessible
- ✅ Database queries are executing properly
- ✅ The Twig templates are rendering

**[Show page source or developer console]**

Everything is served over HTTPS with proper security headers in place."

### Summary Checklist

**Deployment Verification Checklist:**
```
✅ Application starts successfully
✅ Nginx serves traffic on port 80/443
✅ PHP-FPM processes requests
✅ Database connection established
✅ Doctrine migrations executed
✅ File permissions correct (www-data can write to cache)
✅ Home route (/) displays dashboard
✅ Product route (/product) displays product list
✅ Static assets load correctly
✅ HTTPS/SSL working
✅ Response times are fast
✅ No 500 errors in logs
```

---

## CLOSING

"That's the complete deployment pipeline! To summarize:

1. **Dockerfile** provides the recipe for building a production-ready container with PHP-FPM and Nginx
2. **Nginx** efficiently routes web traffic and serves static assets
3. **Environment variables** configure the app for production without changing code
4. **Entrypoint script** orchestrates startup and ensures everything is ready
5. **Railway** handles scaling, monitoring, and hosting

The result is a fully functional, production-grade Symfony application running in the cloud with zero downtime deployments.

If you have questions about any part of this setup, feel free to ask. Thanks for watching!"

---

## VIDEO RECORDING TIPS

### Camera/Screen Setup
- Record at 1920x1080 minimum
- Use a code editor with large font (16pt minimum)
- Have the Railway dashboard accessible in a browser
- Keep the application URL visible in the browser

### Pacing
- Speak clearly and at a moderate pace
- Pause for 2-3 seconds when showing code sections
- Highlight important lines with your cursor/mouse
- Use zoom (CMD/CTRL + Plus) on code when needed

### B-Roll Suggestions
- Show logs scrolling in terminal
- Display the Dockerfile building
- Show Railway deployment progress
- Browser showing the live application
- Show the database schema in phpMyAdmin

### Audio
- Use a microphone (even a decent USB one works)
- Record in a quiet room
- Do multiple takes - editing will make it smooth

### Final Edit (Post-Production)
- Add code syntax highlighting overlays
- Include captions for technical terms
- Show timestamps for each segment
- Add a title card at the beginning
- Include your GitHub repo link at the end
