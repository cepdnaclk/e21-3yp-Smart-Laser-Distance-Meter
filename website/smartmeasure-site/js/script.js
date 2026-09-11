// Mobile nav toggle
const navToggle = document.getElementById("navToggle");
const navLinks = document.getElementById("navLinks");

navToggle.addEventListener("click", () => {
  const isOpen = navLinks.classList.toggle("is-open");
  navToggle.setAttribute("aria-expanded", String(isOpen));
});

// Close mobile menu when a link is tapped
navLinks.querySelectorAll("a").forEach((link) => {
  link.addEventListener("click", () => {
    navLinks.classList.remove("is-open");
    navToggle.setAttribute("aria-expanded", "false");
  });
});

// ============================================================
// Carousel — auto-advances left, plus manual arrows and dots.
// Pauses on hover/focus. Applied to every .carousel on the page.
// ============================================================

function initCarousel(root) {
  const track = root.querySelector(".carousel__track");
  const slides = Array.from(root.querySelectorAll(".carousel__slide"));
  if (slides.length <= 1) return;

  const prevBtn = root.querySelector(".carousel__arrow--prev");
  const nextBtn = root.querySelector(".carousel__arrow--next");
  const dotsWrap = root.querySelector(".carousel__dots");
  let index = 0;
  let timer = null;
  const AUTO_MS = 4500;

  slides.forEach((_, i) => {
    const dot = document.createElement("button");
    dot.className = "carousel__dot" + (i === 0 ? " is-active" : "");
    dot.setAttribute("aria-label", `Go to slide ${i + 1}`);
    dot.addEventListener("click", () => goTo(i));
    dotsWrap.appendChild(dot);
  });
  const dots = Array.from(dotsWrap.children);

  function render() {
    track.style.transform = `translateX(-${index * 100}%)`;
    dots.forEach((d, i) => d.classList.toggle("is-active", i === index));
    slides.forEach((slide, i) => {
      const video = slide.querySelector("video");
      if (!video) return;
      if (i === index) video.play().catch(() => {});
      else video.pause();
    });
  }

  function goTo(i) {
    index = (i + slides.length) % slides.length;
    render();
  }
  function next() {
    goTo(index + 1);
  }
  function prev() {
    goTo(index - 1);
  }

  nextBtn.addEventListener("click", () => {
    next();
    restart();
  });
  prevBtn.addEventListener("click", () => {
    prev();
    restart();
  });

  function start() {
    timer = setInterval(next, AUTO_MS);
  }
  function stop() {
    clearInterval(timer);
  }
  function restart() {
    stop();
    start();
  }

  root.addEventListener("mouseenter", stop);
  root.addEventListener("mouseleave", start);
  root.addEventListener("focusin", stop);
  root.addEventListener("focusout", start);

  render();
  start();
}

document.querySelectorAll(".carousel").forEach(initCarousel);
