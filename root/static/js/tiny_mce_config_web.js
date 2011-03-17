tinyMCE.init({
    mode: "textareas",
    theme: "advanced",
    content_css: "/src/tiny_mce.css",
    plugins: "tabfocus",
    theme_advanced_resizing: true,
    theme_advanced_resizing_horizontal: false,
    theme_advanced_statusbar_location : "bottom",
    theme_advanced_path : false,
    theme_advanced_buttons1: "bold,italic,underline," 
                            +"bullist,numlist,"
                            +"undo,redo,link,forecolor,backcolor,code",
    theme_advanced_buttons2: "",
    theme_advanced_buttons3: "",
    theme_advanced_buttons4: "",
    tabfocus_elements      : ":prev, :next",
    cleanup : false,
});
