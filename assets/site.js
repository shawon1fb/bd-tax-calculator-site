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

// Nav gets a shadow/border once the page scrolls.
(function () {
  var nav = document.querySelector(".nav");
  if (!nav) return;
  function onScroll() {
    nav.classList.toggle("is-scrolled", window.scrollY > 8);
  }
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });
})();

// Scroll-reveal: fade + rise elements into view once, via IntersectionObserver.
(function () {
  var targets = document.querySelectorAll(".reveal");
  if (!targets.length) return;

  if (!("IntersectionObserver" in window)) {
    targets.forEach(function (el) { el.classList.add("in-view"); });
    return;
  }

  // Stagger direct children of .reveal-stagger containers via a CSS var,
  // so groups (cards, stats) animate in one after another.
  document.querySelectorAll(".reveal-stagger").forEach(function (group) {
    Array.prototype.forEach.call(group.children, function (child, i) {
      child.style.setProperty("--i", i);
    });
  });

  var io = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("in-view");
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.15, rootMargin: "0px 0px -8% 0px" }
  );

  targets.forEach(function (el) { io.observe(el); });
})();

// Count-up animation for stat numbers: <span class="num" data-target="79">
(function () {
  var nums = document.querySelectorAll(".stat .num[data-target]");
  if (!nums.length || !("IntersectionObserver" in window)) return;

  function animate(el) {
    var target = parseFloat(el.getAttribute("data-target"));
    var suffix = el.getAttribute("data-suffix") || "";
    var duration = 1100;
    var start = null;

    function step(ts) {
      if (start === null) start = ts;
      var progress = Math.min((ts - start) / duration, 1);
      var eased = 1 - Math.pow(1 - progress, 3); // ease-out-cubic
      var value = Math.round(target * eased);
      el.textContent = value + suffix;
      if (progress < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  }

  var io = new IntersectionObserver(
    function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          animate(entry.target);
          io.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.4 }
  );
  nums.forEach(function (el) { io.observe(el); });
})();
