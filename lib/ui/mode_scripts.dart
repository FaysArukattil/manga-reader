/// JavaScript that applies the per-series reading mode inside the page.
/// Uses a constructable stylesheet first (works even on pages with strict
/// CSP), falling back to a <style> element.
class ModeScripts {
  ModeScripts._();

  static String apply(int mode) {
    final css = switch (mode) {
      // Invert the page, then re-invert media so artwork keeps its colours.
      1 =>
        'html{filter:invert(1) hue-rotate(180deg)!important;background:#fff!important}'
            'img,picture,video,canvas,iframe{filter:invert(1) hue-rotate(180deg)!important}',
      // Warm, slightly dimmed paper tone.
      2 => 'html{filter:sepia(.45) brightness(.92) contrast(.96)!important}',
      _ => '',
    };
    return '''
(function(){
  var css='$css';
  try{
    if(window.CSSStyleSheet&&document.adoptedStyleSheets!==undefined){
      var sheet=window.__shelfmarkSheet;
      if(!sheet){sheet=new CSSStyleSheet();window.__shelfmarkSheet=sheet;}
      sheet.replaceSync(css);
      var list=Array.prototype.slice.call(document.adoptedStyleSheets);
      if(list.indexOf(sheet)<0){list.push(sheet);document.adoptedStyleSheets=list;}
      return;
    }
  }catch(e){}
  var el=document.getElementById('shelfmark-style');
  if(!css){if(el)el.remove();return;}
  if(!el){el=document.createElement('style');el.id='shelfmark-style';(document.head||document.documentElement).appendChild(el);}
  el.textContent=css;
})();
''';
  }
}
