var ntabs, id, program;

function init_tabs(n, i, p) {
    ntabs = n;
    id = i;
    program = p;
}
function tabs(t) {
    for (var n = 1; n <= ntabs; n++) {
        if (n == t) {
            document.getElementById('tab'+n+'focus').style.display = 'block';
            document.getElementById('tab'+n+'ready').style.display = 'none';
            document.getElementById('content'+n).style.display     = 'block';
        }
        else {
            document.getElementById('tab'+n+'focus').style.display = 'none';
            document.getElementById('tab'+n+'ready').style.display = 'block';
            document.getElementById('content'+n).style.display     = 'none';
        }
    }
    if (id) {
        var el = document.getElementById('editlink');
        if (el != null) {
            el.innerHTML = '<a href="/' + ((program)? 'program': 'rental')
                + '/update/' + id + '/' + t + '">Edit</a>';
        }
    }
    else {
        document.getElementById('hid').innerHTML =
                '<input type=hidden name=section value=' + t + '>';
    }
}
