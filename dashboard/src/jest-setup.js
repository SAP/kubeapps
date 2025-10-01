// Copyright 2018-2023 the Kubeapps contributors.
// SPDX-License-Identifier: Apache-2.0

// This file runs before any modules are imported during Jest test execution
// It provides essential global polyfills that are required by modern packages like undici

/* eslint-disable @typescript-eslint/no-var-requires */
const { TextEncoder, TextDecoder } = require("util");
const { EventEmitter } = require("events");

// Make TextEncoder and TextDecoder available globally
// This is required by undici and other modern packages that expect these to be available
global.TextEncoder = TextEncoder;
global.TextDecoder = TextDecoder;

// MessagePort and MessageChannel polyfills
if (typeof global.MessagePort === "undefined") {
  global.MessagePort = class MessagePort extends EventEmitter {
    constructor() {
      super();
      this.onmessage = null;
      this.onmessageerror = null;
    }

    postMessage(data) {
      // Simple implementation for testing
      if (this.onmessage) {
        this.onmessage({ data });
      }
    }

    start() {
      // Empty implementation for testing
    }

    close() {
      // Empty implementation for testing
    }
  };
}

if (typeof global.MessageChannel === "undefined") {
  global.MessageChannel = class MessageChannel {
    constructor() {
      this.port1 = new global.MessagePort();
      this.port2 = new global.MessagePort();
    }
  };
}

// ReadableStream polyfill for undici
if (typeof global.ReadableStream === "undefined") {
  global.ReadableStream = class ReadableStream {
    constructor(source) {
      this.source = source;
    }

    getReader() {
      return {
        read: () => Promise.resolve({ done: true, value: "undefined" }),
        releaseLock: () => {
          // Empty implementation for testing
        },
        closed: Promise.resolve(),
      };
    }

    cancel() {
      return Promise.resolve();
    }

    pipeTo() {
      return Promise.resolve();
    }
  };
}

// WritableStream polyfill
if (typeof global.WritableStream === "undefined") {
  global.WritableStream = class WritableStream {
    getWriter() {
      return {
        write: () => Promise.resolve(),
        close: () => Promise.resolve(),
        abort: () => Promise.resolve(),
        releaseLock: () => {
          // Empty implementation for testing
        },
      };
    }
  };
}

// TransformStream polyfill
if (typeof global.TransformStream === "undefined") {
  global.TransformStream = class TransformStream {
    constructor() {
      this.readable = new global.ReadableStream();
      this.writable = new global.WritableStream();
    }
  };
}

// File and Blob polyfills
if (typeof global.File === "undefined") {
  global.File = class File {
    constructor(fileChunks, filename, options = {}) {
      this.name = filename;
      this.size = 0;
      this.type = options.type || "";
      this.lastModified = Date.now();
    }
  };
}

if (typeof global.Blob === "undefined") {
  global.Blob = class Blob {
    constructor(blobChunks = [], options = {}) {
      this.size = 0;
      this.type = options.type || "";
    }

    slice() {
      return new global.Blob();
    }

    text() {
      return Promise.resolve("");
    }

    arrayBuffer() {
      return Promise.resolve(new ArrayBuffer(0));
    }
  };
}

// FormData polyfill
if (typeof global.FormData === "undefined") {
  global.FormData = class FormData {
    constructor() {
      this.data = new Map();
    }

    append(key, value) {
      this.data.set(key, value);
    }

    get(key) {
      return this.data.get(key);
    }

    has(key) {
      return this.data.has(key);
    }
  };
}

// Also provide fetch-related globals that might be needed
if (typeof global.fetch === "undefined") {
  // These will be available if needed, but we don't want to override existing implementations
  global.fetch = jest.fn();
  global.Request = jest.fn();
  global.Response = jest.fn();
  global.Headers = jest.fn();
}
