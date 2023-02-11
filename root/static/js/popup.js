var new_win;
function popup(url, height, width) {
    newwin = window.open(
        url,
        'popup',      // target
        'height=' + height + ',width=' + width + ', scrollbars'
    );
    if (window.focus) {
        newwin.focus();
    }
    newwin.moveTo(700, 0);
}
