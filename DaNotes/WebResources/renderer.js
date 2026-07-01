// Markdown + math rendering pipeline.
// Depends on marked.min.js and MathJax (tex-svg.js) being loaded beforehand.
// Exposes `window.__daNotesRender(markdown)` which the Swift layer calls.
(function () {
  'use strict';

  function escapeHtml(s) {
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  // marked extension: capture `$...$` / `$$...$$` verbatim (bypassing Markdown
  // emphasis/escaping) and emit MathJax delimiters.
  var mathExtension = {
    extensions: [
      {
        name: 'blockMath',
        level: 'block',
        start: function (src) { var i = src.indexOf('$$'); return i < 0 ? undefined : i; },
        tokenizer: function (src) {
          var m = /^\$\$([\s\S]+?)\$\$/.exec(src);
          if (m) { return { type: 'blockMath', raw: m[0], text: m[1].trim() }; }
        },
        renderer: function (token) {
          return '<div class="math-display">\\[' + escapeHtml(token.text) + '\\]</div>\n';
        }
      },
      {
        name: 'inlineMath',
        level: 'inline',
        start: function (src) { var i = src.indexOf('$'); return i < 0 ? undefined : i; },
        tokenizer: function (src) {
          var m = /^\$(?!\$)((?:\\.|[^$\\\n])+?)\$/.exec(src);
          if (m) { return { type: 'inlineMath', raw: m[0], text: m[1] }; }
        },
        renderer: function (token) {
          return '\\(' + escapeHtml(token.text) + '\\)';
        }
      }
    ]
  };

  if (window.marked) {
    marked.use({ gfm: true, breaks: false });
    marked.use(mathExtension);
  }

  window.__daNotesRender = async function (md) {
    var content = document.getElementById('content');
    try {
      if (window.MathJax && MathJax.typesetClear) {
        try { MathJax.typesetClear(); } catch (e) {}
      }
      content.innerHTML = window.marked ? marked.parse(md) : '';
      if (window.MathJax && MathJax.startup) {
        await MathJax.startup.promise;
        await MathJax.typesetPromise([content]);
      }
    } catch (e) {
      console.error('render error', e);
    }
    var height = document.body.scrollHeight;
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.rendered) {
      window.webkit.messageHandlers.rendered.postMessage(height);
    }
    return height;
  };
})();
