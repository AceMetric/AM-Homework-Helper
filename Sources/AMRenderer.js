/* Trusted offline renderer. Material is data, never an executable page. */
(() => {
  const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let sequence=0;
  window.AMRender=async function(input){
    const ticket=++sequence;
    if(input.image && /^am-preview:\/\/image\/[a-z0-9-]+$/.test(input.image)){const r=input.region;const region=Array.isArray(r)&&r.length===4&&r.every(x=>typeof x==='number'&&x>=0&&x<=1)?'<div style="position:absolute;pointer-events:none;border:3px solid #e08018;box-sizing:border-box;left:'+(r[0]*100)+'%;top:'+(r[1]*100)+'%;width:'+(r[2]*100)+'%;height:'+(r[3]*100)+'%"></div>':'';document.getElementById('content').innerHTML='<figure style="position:relative;display:inline-block;margin:0;max-width:100%"><img style="display:block" alt="作业图片" src="'+input.image+'">'+region+'</figure>';return {completed:true,issues:[],formulaCount:0};}
    const source=String(input.text||'');const issues=[];const formulas=[];if(source.length>1000000){document.getElementById('content').textContent='内容超过安全预览限制，请查看源码。';return {completed:false,issues:[],formulaCount:0};}
    const md=markdownit({html:true,linkify:false,typographer:false});
    const blockOpen=md.renderer.rules.paragraph_open;md.renderer.rules.paragraph_open=(tokens,i,options,env,self)=>{if(tokens[i].map)tokens[i].attrSet('data-line',String(tokens[i].map[0]+1));return blockOpen?blockOpen(tokens,i,options,env,self):self.renderToken(tokens,i,options);};
    md.inline.ruler.before('escape','am_math',(state,silent)=>{
      const start=state.pos;if(state.src[start]!=='$' || state.src[start+1]==='$')return false;const prefix=(state.src.slice(0,start).match(/\S*$/)||[''])[0];if(/[\/\\]/.test(prefix)&&!prefix.includes('$'))return false;
      const wrapped=state.src[start+1]==='`';const opening=wrapped?2:1;const delimiter=wrapped?'`$':'$';
      if(!wrapped && /\s/.test(state.src[start+1]||' '))return false;
      let end=state.src.indexOf(delimiter,start+opening);
      while(end>=0 && state.src[end-1]==='\\')end=state.src.indexOf(delimiter,end+delimiter.length);
      if(end<0){if((/[\\_^{}]/.test(state.src.slice(start+1)) || /^[a-z][a-z\d\s().]*[+*=<>]/i.test(state.src.slice(start+1))) && !silent){const token=state.push('am_unclosed','',0);token.content=state.src.slice(start);token.meta={relative:state.src.slice(0,start).split('\n').length-1};state.pos=state.src.length;return true;}return false;}
      const tex=state.src.slice(start+opening,end);
      if(!tex.trim() || (!wrapped && (/\s$/.test(tex) || /^\d[\d,.]*\s/.test(tex))))return false;
      if(!silent){const token=state.push('am_math','',0);token.content=tex;token.meta={relative:state.src.slice(0,start).split('\n').length-1};}
      state.pos=end+delimiter.length;return true;
    });
    md.block.ruler.before('fence','am_math_block',(state,start,end,silent)=>{
      const line=state.src.slice(state.bMarks[start]+state.tShift[start],state.eMarks[start]);if(!line.startsWith('$$'))return false;
      if(silent)return true;let last=start,body=line.slice(2),closed=false;
      if(body.endsWith('$$')){body=body.slice(0,-2);closed=true;}
      else{const lines=[body];for(last=start+1;last<end;last++){const text=state.src.slice(state.bMarks[last],state.eMarks[last]);const at=text.indexOf('$$');if(at>=0){lines.push(text.slice(0,at));closed=true;break;}lines.push(text);}body=lines.join('\n');}
      const token=state.push('am_math_block','',0);token.content=body;token.map=[start,Math.min(last+1,end)];token.meta={line:start+1,closed};state.line=Math.min(last+1,end);return true;
    });
    md.core.ruler.after('inline','am_locations',state=>{for(const parent of state.tokens){if(parent.type==='inline')for(const child of parent.children||[])if(child.type.startsWith('am_'))child.meta.line=(parent.map?.[0]||0)+1+(child.meta.relative||0);}});
    const placeholder=(tex,line,display)=>{const id=formulas.length;formulas.push({id,tex,line,display});return `<${display?'div':'span'} id="am-formula-${id}" class="am-formula" data-line="${line}"></${display?'div':'span'}>`;};
    md.renderer.rules.am_math=(tokens,i)=>placeholder(tokens[i].content,tokens[i].meta.line,false);
    md.renderer.rules.am_unclosed=(tokens,i)=>{const t=tokens[i];issues.push({line:t.meta.line,severity:'warning',message:'疑似未闭合行内公式',evidence:t.content,suggestion:'核对 GitHub 公式分隔符；货币或普通美元符号可忽略。'});return esc(t.content);};
    md.renderer.rules.am_math_block=(tokens,i)=>{const t=tokens[i];if(!t.meta.closed)issues.push({line:t.meta.line,severity:'error',message:'块公式未闭合',evidence:'$$',suggestion:'补齐块公式的结束分隔符。'});return placeholder(t.content,t.meta.line,true);};
    const fence=md.renderer.rules.fence;md.renderer.rules.fence=(tokens,i,options,env,self)=>tokens[i].info.trim()==='math'?placeholder(tokens[i].content,tokens[i].map[0]+1,true):fence(tokens,i,options,env,self);
    let html=md.render(source);html=DOMPurify.sanitize(html,{USE_PROFILES:{html:true},FORBID_TAGS:['script','style','iframe','object','embed','form','input','textarea','button','link','meta','base'],FORBID_ATTR:['style','srcset']});
    document.getElementById('content').innerHTML=html;window.scrollTo(0,0);
    for(const img of document.querySelectorAll('#content img')){img.loading='lazy';img.decoding='async';const original=img.getAttribute('src')||'';const safe=input.images?.[original];if(safe && safe.startsWith('am-preview://image/'))img.src=safe;else{img.removeAttribute('src');img.alt=img.alt||'图片不可用／未获取';}}
    for(const a of document.querySelectorAll('#content a')){a.title=a.getAttribute('href')||'';a.removeAttribute('href');}
    for(const paragraph of document.querySelectorAll('#content p')){const copy=paragraph.cloneNode(true);copy.querySelectorAll('.am-formula,code,pre').forEach(n=>n.remove());const prose=copy.textContent.split(/\s+/).filter(word=>!(/^[A-Za-z]:[\/\\]/.test(word)||/^[^\\]*\/.*\\/.test(word))).join(' ');if(/\\(?:frac|mathbf|boldsymbol|begin|times|sqrt)\b/.test(prose))issues.push({line:Number(paragraph.dataset.line)||1,severity:'warning',message:'疑似裸露的公式命令／兼容问题',evidence:copy.textContent.slice(0,240),suggestion:'核对公式是否被 Markdown 转义或强调拆开；对照源码与预览，必要时使用 GitHub 的美元加反引号分隔方式。'});}
    if(formulas.length>512)return {completed:false,issues,formulaCount:formulas.length};
    await MathJax.startup.promise;
    for(const item of formulas){if(ticket!==sequence)return {completed:false,issues:[],formulaCount:0};const target=document.getElementById('am-formula-'+item.id);if(!target)continue;
      try{const node=await MathJax.tex2svgPromise(item.tex,{display:item.display});if(ticket!==sequence)return {completed:false,issues:[],formulaCount:0};target.appendChild(node);const bad=node.querySelector('[data-mjx-error],[data-mml-node="merror"]');if(bad){const reason=bad.getAttribute('data-mjx-error')||bad.textContent||'公式解析未完成';issues.push({line:item.line,severity:/undefined|unknown/i.test(reason)?'warning':'error',message:'公式渲染未完成：'+reason.slice(0,160),evidence:item.tex,suggestion:'核对命令、括号与环境；扩展命令可能与 GitHub 配置不同。'});}}
      catch(error){target.textContent=item.tex;issues.push({line:item.line,severity:'warning',message:'公式渲染未完成',evidence:item.tex,suggestion:'核对公式；不代表数学结论有误。'});}
      if(target.scrollWidth>document.getElementById('content').clientWidth+2)issues.push({line:item.line,severity:'info',message:'公式较宽，窄窗口需要横向滚动',evidence:item.tex,suggestion:'核对 GitHub 预览，可考虑分行；这是布局提示。'});
    }
    document.documentElement.dataset.appearance=input.dark?'dark':'light';
    return {issues,formulaCount:formulas.length,completed:true};
  };
})();
