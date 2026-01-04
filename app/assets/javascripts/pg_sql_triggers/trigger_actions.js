// AJAX handlers for trigger actions
(function() {
  'use strict';

  // Handle AJAX form submissions
  document.addEventListener('DOMContentLoaded', function() {
    // Set up AJAX error handling
    document.addEventListener('ajax:error', function(event) {
      const detail = event.detail || [];
      const error = detail[0] || {};
      const status = error.status || 500;
      const message = error.message || 'An error occurred';

      alert('Error: ' + message);
      console.error('AJAX Error:', error);
    });

    // Handle AJAX success for trigger actions
    document.addEventListener('ajax:success', function(event) {
      const [data, status, xhr] = event.detail;
      
      // If the response contains a redirect, follow it
      if (xhr.getResponseHeader('Location')) {
        window.location.href = xhr.getResponseHeader('Location');
      } else {
        // Otherwise, reload the page to show updated state
        window.location.reload();
      }
    });

    // Handle AJAX complete to show loading states
    document.addEventListener('ajax:before', function(event) {
      const form = event.target;
      const submitButton = form.querySelector('button[type="submit"], button[type="button"]');
      if (submitButton) {
        submitButton.disabled = true;
        submitButton.textContent = 'Processing...';
      }
    });

    document.addEventListener('ajax:complete', function(event) {
      const form = event.target;
      const submitButton = form.querySelector('button[type="submit"], button[type="button"]');
      if (submitButton) {
        submitButton.disabled = false;
      }
    });
  });
})();

