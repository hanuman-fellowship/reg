var red;
var green;
var blue;
var incr = 10;

function hex(n) {
    var s = n.toString(16);
    if (s.length == 1) {
        s = '0' + s;
    }
    return s;
}

function adjust(r, g, b) {
    red   += r;
    green += g;
    blue  += b;
    red   = Math.min(Math.max(red,   0), 255);
    green = Math.min(Math.max(green, 0), 255);
    blue  = Math.min(Math.max(blue,  0), 255);
    document.getElementById('swatch').style.background =
        '#' + hex(red) + hex(green) + hex(blue);
    document.getElementById('color_val').value =
        red + ", " + green + ", " + blue;
                                         
}

function colorSet(r, g, b) {
    red = r;
    green = g;
    blue =  b;
    adjust(0, 0, 0);
    document.getElementById('swatch').style.background = 
            '#' + hex(red) + hex(green) + hex(blue);
}
