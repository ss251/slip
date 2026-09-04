(function(){
  function wrap(u8){ u8.toString = function(enc){ if (enc==='hex') return Array.from(this,b=>b.toString(16).padStart(2,'0')).join(''); return Uint8Array.prototype.toString.call(this); }; return u8; }
  globalThis.Buffer = { from(x, enc){
    if (typeof x === 'string' && enc === 'hex'){ const a=new Uint8Array(x.length/2); for(let i=0;i<a.length;i++) a[i]=parseInt(x.substr(i*2,2),16); return wrap(a); }
    return wrap(x instanceof Uint8Array ? x : new Uint8Array(x)); } };
})();
