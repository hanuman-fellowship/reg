$(document).ready(function () {
  //Menu button on click event
  $('.selectors').on('click', function() {
       
// Toggles a class that slides the menu into view on the screen
    $('.mobile-menu').toggleClass('mobile-menu--open');
// This triggers the nav items slide-in
     $(".slide-in").addClass('animated');
    setTimeout(function() {
          $(".slide-in").removeClass('animated');
    }, 1500);
// Toggles the mobile button cross-change
    $('.bar-icon').toggleClass('active');
    $('.icon-wrapper').toggleClass('closingwr');
    return false;
  }); 
});


