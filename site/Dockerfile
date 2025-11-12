# Use Node.js LTS version
FROM node:22-alpine

# Set working directory
WORKDIR /app

# Install git (needed for some npm packages)
RUN apk add --no-cache git

# Copy package.json and package-lock.json (if available)
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production=false

# Copy the rest of the application code
COPY . .

# Expose port 3000
EXPOSE 3000

# Default command for development
CMD ["npm", "start", "--", "--host", "0.0.0.0"]

# For production build, you can override with:
# docker run kubeapps-docs npm run build
