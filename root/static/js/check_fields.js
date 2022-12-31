function check_fields() {
    var mess = '';
    var focus = 0;
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
                    var el = document.getElementById(fld.name + '1');
                    el.scrollIntoView();
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
                    focus = 1;
                    el.focus();
                }
            }
        }
    }
    if (mess === '') {
        var el = document.getElementById('submit');
        el.disabled = true; // no double clicking...
        el.value = 'Sending...';
        return true;
    }
    else {
        alert(mess);
        return false;
    }
}
