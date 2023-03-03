function check_fields() {
    var mess = '';
    var focus = 0;
    var focus_el;
    for (f in fields) {
        fld = fields[f];
        if (fld.id === 'radio') {
            var chk = document.querySelector(
                          'input[name="'
                          + fld.name
                          + '"]:checked'
                      );
            if (chk == null) {
                if (focus == 0) {
                    focus_el = document.getElementById(fld.name + '1');
                    focus = 1;
                }
                mess += fld.err + '\n';
            }
        }
        else {
            var el = document.getElementById(fld.id);
            var regexp = new RegExp(fld.regexp);
            if (! regexp.test(el.value)) {
                mess += fld.err + '\n';
                if (focus == 0 ){
                    focus_el = el;
                    focus = 1;
                }
            }
        }
    }
    if (mess === '') {
        //var el = document.getElementById('submit');
        //el.disabled = true; // no double clicking...
        //el.value = 'Sending...';
        return true;
    }
    else {
        alert(mess);
        setTimeout(function() {
            focus_el.focus();
            focus_el.scrollIntoView();
        }, 0);
        return false;
    }
}
