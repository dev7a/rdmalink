// The Why diagrams' Pause buttons. Both buttons toggle one state, data-paused on the
// section, which pauses every animation in both diagrams (see tools/why.py). They stay
// hidden without JavaScript, and styles.css hides them under reduced motion, where the
// diagrams are already still. The diagrams also pause while they are off screen
// (data-offscreen, kept apart from the reader's Pause); one observer on both figures keeps
// them in step.
(function () {
  'use strict';
  var why = document.getElementById('why');
  if (!why) return;
  var buttons = why.querySelectorAll('.why-pause');
  for (var i = 0; i < buttons.length; i++) {
    buttons[i].hidden = false;
    buttons[i].addEventListener('click', function () {
      why.setAttribute('data-paused', why.getAttribute('data-paused') === 'true' ? 'false' : 'true');
    });
  }
  var figs = why.querySelector('.why-figs');
  if (figs && 'IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      why.setAttribute('data-offscreen', entries[entries.length - 1].isIntersecting ? 'false' : 'true');
    }).observe(figs);
  }
})();
