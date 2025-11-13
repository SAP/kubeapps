# Website

This website is built using [Docusaurus](https://docusaurus.io/), a modern static website generator.

## Installation

### Local Development (Node.js required)

```bash
npm install
```

### Docker Development (no local dependencies required)

Build and run with Docker:

```bash
# Build the Docker image
docker build -t kubeapps-docs .

# Run development server
docker run -p 3000:3000 -v $(pwd):/app -w /app kubeapps-docs

# Or run in interactive mode for development
docker run -it -p 3000:3000 -v $(pwd):/app -w /app kubeapps-docs bash
```

## Local Development

```bash
npm start
```

This command starts a local development server and opens up a browser window. Most changes are reflected live without having to restart the server.

## Build

```bash
npm run build
```

This command generates static content into the `build` directory and can be served using any static contents hosting service.
