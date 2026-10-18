/* Trusted offline renderer. Material is data, never an executable page. */
(() => {
  const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  let sequence=0;
  const style=document.createElement('style');style.textContent=`
.am-plain{font:12px ui-monospace,monospace;padding:12px;background:color-mix(in srgb,var(--ink) 7%,var(--paper));border-radius:6px}.am-plain pre{margin:0;padding:0;min-height:1.6em;background:none;white-space:pre}.am-plain pre.am-text-mark{padding-left:8px;padding-right:28px}
.am-image{position:relative;display:inline-block;margin:0;max-width:100%}.am-image>img{display:block}
.am-annotation-box{position:absolute;border:2px solid #d70015;box-sizing:border-box;pointer-events:none}.am-text-mark{position:relative;border-left:2px solid #d70015;padding-left:8px}
.am-note{position:absolute;right:0;top:0;pointer-events:auto}.am-note-trigger{width:26px;height:26px;border:0;border-radius:6px;background:#d70015;color:white;padding:4px;cursor:pointer}.am-note-trigger svg{fill:none;stroke:currentColor;stroke-width:1.8;width:18px;height:18px}.am-note-trigger:focus-visible{outline:3px solid #087dff;outline-offset:2px}
.am-note-body{position:fixed;z-index:100;width:min(360px,calc(100vw - 48px));max-height:calc(70vh - 24px);overflow:auto;padding:14px;border:1px solid var(--line);border-radius:10px;background:var(--paper);color:var(--ink);box-shadow:0 5px 24px #0004;font-size:13px;line-height:1.5;cursor:auto;box-sizing:border-box}.am-note-body[hidden]{display:none}.am-note-body>:first-child{margin-top:0}.am-note-body>:last-child{margin-bottom:0}.am-note-body h2,.am-note-body h3{font-size:14px}.am-note[data-selected=true]{z-index:2}.am-note[data-selected=true]>.am-note-trigger{outline:2px solid var(--paper);outline-offset:1px}
`;document.head.append(style);
  window.AMRender=async function(input){
    const ticket=++sequence;
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
    const direct=typeof input.image==='string' && /^am-preview:\/\/image\/[a-z0-9-]+$/.test(input.image);
    const plain=input.plain===true;
    const plainHTML=()=>{const marked=new Set([1,...(input.annotations||[]).map(n=>Number(n.line)||1)]),chunks=[],buffer=[];const flush=()=>{if(buffer.length){chunks.push('<pre>'+esc(buffer.join('\n'))+'</pre>');buffer.length=0;}};for(const [index,line] of source.split('\n').entries()){if(marked.has(index+1)){flush();chunks.push('<pre data-line="'+(index+1)+'">'+esc(line||' ')+'</pre>');}else buffer.push(line);}flush();return '<div class="am-plain">'+chunks.join('')+'</div>';};
    let html=direct?'<figure class="am-image"><img alt="作业图片" src="'+input.image+'"></figure>':plain?plainHTML():md.render(source);if(!direct)html=DOMPurify.sanitize(html,{USE_PROFILES:{html:true},FORBID_TAGS:['script','style','iframe','object','embed','form','input','textarea','button','link','meta','base'],FORBID_ATTR:['style','srcset']});
    document.getElementById('content').innerHTML=html;window.scrollTo(0,0);
    for(const img of document.querySelectorAll('#content img')){img.loading=direct?'eager':'lazy';img.decoding='async';const original=img.getAttribute('src')||'';const safe=(direct && original===input.image)?input.image:input.images?.[original];if(safe && safe.startsWith('am-preview://image/'))img.src=safe;else{img.removeAttribute('src');img.alt=img.alt||'图片不可用／未获取';}}
    for(const a of document.querySelectorAll('#content a')){a.title=a.getAttribute('href')||'';a.removeAttribute('href');}
    for(const paragraph of document.querySelectorAll('#content p')){const copy=paragraph.cloneNode(true);copy.querySelectorAll('.am-formula,code,pre').forEach(n=>n.remove());const prose=copy.textContent.split(/\s+/).filter(word=>!(/^[A-Za-z]:[\/\\]/.test(word)||/^[^\\]*\/.*\\/.test(word))).join(' ');if(/\\(?:frac|mathbf|boldsymbol|begin|times|sqrt)\b/.test(prose))issues.push({line:Number(paragraph.dataset.line)||1,severity:'warning',message:'疑似裸露的公式命令／兼容问题',evidence:copy.textContent.slice(0,240),suggestion:'核对公式是否被 Markdown 转义或强调拆开；对照源码与预览，必要时使用 GitHub 的美元加反引号分隔方式。'});}
    const content=document.getElementById('content');
    const validRegion=r=>Array.isArray(r)&&r.length===4&&r.every(x=>Number.isFinite(x)&&x>=0&&x<=1)&&r[2]>0&&r[3]>0&&r[0]+r[2]<=1&&r[1]+r[3]<=1;
    const annotations=Array.isArray(input.annotations)?input.annotations.slice(0,200):[];
    if(direct && validRegion(input.region) && !annotations.length){const box=document.createElement('div');box.className='am-annotation-box';const r=input.region;Object.assign(box.style,{left:r[0]*100+'%',top:r[1]*100+'%',width:r[2]*100+'%',height:r[3]*100+'%'});content.firstElementChild.append(box);}
    for(const [index,note] of annotations.entries()){
      if(typeof note.markdown!=='string'||note.markdown.length>50000)continue;
      let host;
      if(direct){if(!validRegion(note.region))continue;host=document.createElement('div');host.className='am-annotation-box';const r=note.region;Object.assign(host.style,{left:r[0]*100+'%',top:r[1]*100+'%',width:r[2]*100+'%',height:r[3]*100+'%'});content.firstElementChild.append(host);}
      else{const anchors=[...content.querySelectorAll('[data-line]')];const line=Number(note.line)||1;host=anchors.filter(n=>Number(n.dataset.line)<=line).at(-1)||content.firstElementChild;if(!host)continue;host.classList.add('am-text-mark');}
      const marker=document.createElement('span');marker.className='am-note';marker.dataset.annotation=String(note.id||index);host.append(marker);
      const button=document.createElement('button');button.className='am-note-trigger';button.type='button';button.setAttribute('aria-label','查看批注');button.setAttribute('aria-expanded','false');button.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 4h14a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H9l-5 4v-4H3V6a2 2 0 0 1 2-2Z"/><path d="M7 9h10M7 13h7"/></svg>';
      const popup=document.createElement('aside');popup.className='am-note-body';popup.hidden=true;popup.setAttribute('role','dialog');popup.setAttribute('aria-label','批注');popup.id='am-note-'+index;button.setAttribute('aria-controls',popup.id);
      popup.innerHTML=DOMPurify.sanitize(md.render(note.markdown),{USE_PROFILES:{html:true},FORBID_TAGS:['script','style','iframe','object','embed','form','input','textarea','button','link','meta','base','img'],FORBID_ATTR:['style','srcset']});
      popup.querySelectorAll('a').forEach(a=>a.removeAttribute('href'));marker.append(button,popup);
      const hide=()=>{popup.hidden=true;button.setAttribute('aria-expanded','false');};
      const show=()=>{document.querySelectorAll('.am-note-body').forEach(p=>{if(p!==popup){p.hidden=true;p.previousElementSibling?.setAttribute('aria-expanded','false');}});popup.hidden=false;button.setAttribute('aria-expanded','true');const b=button.getBoundingClientRect(),p=popup.getBoundingClientRect();popup.style.left=Math.max(12,Math.min(b.left,innerWidth-p.width-12))+'px';popup.style.top=Math.max(12,Math.min(b.bottom+8,innerHeight-p.height-12))+'px';};
      marker.addEventListener('mouseenter',show);marker.addEventListener('mouseleave',()=>{if(!marker.contains(document.activeElement))hide();});button.addEventListener('focus',show);button.addEventListener('click',show);marker.addEventListener('focusout',event=>{if(!marker.contains(event.relatedTarget))hide();});marker.addEventListener('keydown',event=>{if(event.key==='Escape'){hide();event.stopPropagation();}});
      if(String(note.id)===String(input.selected)){marker.dataset.selected='true';requestAnimationFrame(()=>marker.scrollIntoView({block:'center'}));}
    }
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
