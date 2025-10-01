// Copyright 2022 the Kubeapps contributors.
// SPDX-License-Identifier: Apache-2.0

const webpack = require("webpack");
const NodePolyfillPlugin = require("node-polyfill-webpack-plugin");
const MonacoWebpackPlugin = require("monaco-editor-webpack-plugin");

module.exports = {
  webpack: {
    configure: {
      plugins: [
        // add the required polyfills (not included in webpack 5)
        new NodePolyfillPlugin({
          // Allow using console.log
          excludeAliases: ["console"],
        }),
        new webpack.ProvidePlugin({
          process: "process/browser.js",
          Buffer: ["buffer", "Buffer"],
        }),
        new MonacoWebpackPlugin({
          // see https://github.com/microsoft/monaco-editor/tree/main/webpack-plugin
          languages: ["yaml", "json"],
        }),
      ],
      ignoreWarnings: [/Failed to parse source map/], // ignore source map warnings
    },
  },
  jest: {
    configure: {
      setupFiles: ["<rootDir>/src/jest-setup.js"],
      moduleNameMapper: {
        "^cheerio/lib/utils$": "<rootDir>/src/__mocks__/cheerio-utils.js",
        "^cheerio/lib/(.*)$": "<rootDir>/src/__mocks__/cheerio-$1.js",
      },
      transformIgnorePatterns: [
        "node_modules/(?!(cheerio|axios|@bufbuild|@cds|@clr|@connectrpc|@lit|@lit-labs|lit|lit-html|lit-element|bail|ccount|cds|character-entities|comma-separated-tokens|decode-named-character-reference|escape-string-regexp|hast-util-whitespace|is-plain-obj|lodash-es|markdown-table|mdast-util-definitions|mdast-util-find-and-replace|mdast-util-from-markdown|mdast-util-gfm-autolink-literal|mdast-util-gfm|mdast-util-newline-to-break|mdast-util-to-hast|mdast-util-to-markdown|mdast-util-to-string|micromark-core-commonmark|micromark|monaco-editor|parse-entities|property-information|ramda|react-markdown|react-monaco-editor|react-syntax-highlighter|remark-breaks|remark-gfm|remark-parse|remark-rehype|space-separated-tokens|swagger-client|swagger-ui-react|trim-lines|trough|unified|unist-builder|unist-util-generated|unist-util-is|unist-util-position|unist-util-stringify-position|unist-util-visit-parents|unist-util-visit|util-find-and-replace|vfile-message|vfile)/)",
      ],
    },
  },
};
