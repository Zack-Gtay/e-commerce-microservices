(function () {
    'use strict';

    document.querySelectorAll('[data-stepper]').forEach(function (stepper) {
        var input = stepper.querySelector('[data-stepper-input]');
        if (!input) return;

        var min = parseInt(input.getAttribute('min'), 10) || 1;
        var max = parseInt(input.getAttribute('max'), 10) || 99;

        function nudge(delta) {
            var current = parseInt(input.value, 10);
            if (isNaN(current)) current = min;
            var next = Math.min(max, Math.max(min, current + delta));
            input.value = next;
            input.dispatchEvent(new Event('change', { bubbles: true }));
        }

        stepper.querySelectorAll('[data-stepper-dec]').forEach(function (btn) {
            btn.addEventListener('click', function () { nudge(-1); });
        });
        stepper.querySelectorAll('[data-stepper-inc]').forEach(function (btn) {
            btn.addEventListener('click', function () { nudge(1); });
        });

        input.addEventListener('blur', function () {
            var value = parseInt(input.value, 10);
            if (isNaN(value)) value = min;
            input.value = Math.min(max, Math.max(min, value));
        });
    });

    document.querySelectorAll('[data-validate]').forEach(function (form) {
        form.addEventListener('submit', function (event) {
            if (!form.checkValidity()) {
                event.preventDefault();
                event.stopPropagation();
                var firstInvalid = form.querySelector(':invalid');
                if (firstInvalid) firstInvalid.focus();
            }
            form.classList.add('was-validated');
        });
    });

    document.querySelectorAll('[data-submit-once]').forEach(function (form) {
        form.addEventListener('submit', function () {
            if (!form.checkValidity()) return;
            form.querySelectorAll('button[type="submit"]').forEach(function (btn) {
                btn.classList.add('is-disabled');
                btn.setAttribute('aria-busy', 'true');
            });
        });
    });
})();
