// Copyright 2018-2023 the Kubeapps contributors.
// SPDX-License-Identifier: Apache-2.0

// Mock for cheerio/lib/utils to maintain compatibility with enzyme
module.exports = {
  isCheerio: function(obj) {
    return obj && typeof obj === 'object' && obj._root && obj._options;
  },

  camelCase: function(str) {
    return str.replace(/-([a-z])/g, function(match, letter) {
      return letter.toUpperCase();
    });
  },

  cssCase: function(str) {
    return str.replace(/[A-Z]/g, function(match) {
      return '-' + match.toLowerCase();
    });
  },

  domEach: function(array, fn) {
    var len = array.length;
    for (var i = 0; i < len; i++) fn.call(array, i, array[i]);
    return array;
  },

  cloneDom: function(dom) {
    return dom; // Simple implementation for testing
  }
};
