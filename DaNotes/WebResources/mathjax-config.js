// MathJax configuration. Must be evaluated before tex-svg.js is loaded.
// Math is delivered to MathJax via \( \) and \[ \] delimiters that the marked
// extension in renderer.js produces from the Markdown `$...$` / `$$...$$` syntax.
window.MathJax = {
  tex: {
    inlineMath: [['\\(', '\\)']],
    displayMath: [['\\[', '\\]']]
  },
  svg: { fontCache: 'local' },
  options: { enableMenu: false },
  startup: { typeset: false }
};
