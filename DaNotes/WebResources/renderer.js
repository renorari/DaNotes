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

  // marked extension: render `#tag` as a tappable chip, mirroring
  // `HashtagParser` on the Swift side (boundary before `#`, stops at
  // whitespace/`#`, trailing punctuation left as plain text).
  var hashtagExtension = {
    extensions: [
      {
        name: 'hashtag',
        level: 'inline',
        start: function (src) {
          var m = /(^|\s)#[^\s#]/.exec(src);
          return m ? m.index + m[1].length : undefined;
        },
        tokenizer: function (src) {
          var m = /^#([^\s#]+)/.exec(src);
          if (!m) { return; }
          var trail = /[.,!?;:)\]}、。!?」』】,]+$/.exec(m[1]);
          var tag = trail ? m[1].slice(0, m[1].length - trail[0].length) : m[1];
          if (!tag) { return; }
          return { type: 'hashtag', raw: '#' + tag, text: tag };
        },
        renderer: function (token) {
          return '<span class="hashtag" data-tag="' + escapeHtml(token.text) + '">#' + escapeHtml(token.text) + '</span>';
        }
      }
    ]
  };

  if (window.marked) {
    marked.use({ gfm: true, breaks: false });
    marked.use(mathExtension);
    marked.use(hashtagExtension);
  }

  // Lets the native layer offer markup on an existing image, and filter by a
  // tapped hashtag: delegated on `document` so it keeps working after
  // `content.innerHTML` is replaced on every render.
  document.addEventListener('click', function (event) {
    var target = event.target;
    if (!target) { return; }
    if (target.tagName === 'IMG' && target.closest('#content')) {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.imageTapped) {
        var src = target.getAttribute('src');
        if (src) { window.webkit.messageHandlers.imageTapped.postMessage(src); }
      }
      return;
    }
    var hashtagEl = target.closest('.hashtag');
    if (hashtagEl && hashtagEl.closest('#content')) {
      var tag = hashtagEl.getAttribute('data-tag');
      if (tag && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.hashtagTapped) {
        window.webkit.messageHandlers.hashtagTapped.postMessage(tag);
      }
    }
  });

  // `index` counts only top-level headings, matching the native outline,
  // which skips headings nested in quotes and lists.
  window.__daNotesScrollToHeading = function (index) {
    var headings = document.querySelectorAll(
      '#content > h1, #content > h2, #content > h3, #content > h4, #content > h5, #content > h6'
    );
    var heading = headings[index];
    if (heading) { heading.scrollIntoView({ behavior: 'smooth', block: 'start' }); }
  };

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
