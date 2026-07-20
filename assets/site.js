// Language toggle (English / বাংলা) with localStorage persistence.
(function () {
  var KEY = "bdtax-lang";
  var root = document.documentElement;

  function apply(lang) {
    root.setAttribute("data-lang", lang);
    root.setAttribute("lang", lang === "bn" ? "bn" : "en");
    document.querySelectorAll("[data-lang-toggle]").forEach(function (btn) {
      // The button shows the language it will switch TO.
      btn.textContent = lang === "bn" ? "English" : "বাংলা";
    });
  }

  var saved = localStorage.getItem(KEY) || "en";
  apply(saved);

  document.addEventListener("click", function (e) {
    var btn = e.target.closest("[data-lang-toggle]");
    if (!btn) return;
    var next = root.getAttribute("data-lang") === "bn" ? "en" : "bn";
    localStorage.setItem(KEY, next);
    apply(next);
  });
})();
