$(document).ready(function() {
  addExternalLinks();
});

addExternalLinks = function() {
  $('A[rel="external"]').each(function() {
    $(this).attr('alt', 'Link opens in new window.');
    $(this).attr('title', 'Link opens in new window.');
    $(this).attr('target', '_blank');
  });
};
