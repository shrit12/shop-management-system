// Explicitly created disposable QA accounts only. Reads password through hidden stdin.
import fs from 'node:fs/promises';import vm from 'node:vm';import assert from 'node:assert/strict';import {randomUUID} from 'node:crypto';
if(process.stdin.isTTY)process.stdin.setRawMode(true);process.stdin.resume();console.log('Ready for QA password on hidden stdin.');
const password=await new Promise(resolve=>{let s='';process.stdin.on('data',chunk=>{s+=chunk.toString();if(s.includes('\n')){process.stdin.pause();resolve(s.trim())}})});
let ctx={window:{}};vm.runInNewContext(await fs.readFile('dist/config.js','utf8'),ctx);const c=ctx.window.SHOP_BACKEND;
const sessions=[],userIds={};let checks=0;
async function call(path,token,{method='GET',body}={}){const r=await fetch(c.url+path,{method,headers:{apikey:c.publishableKey,...(token?{Authorization:'Bearer '+token}:{}),...(body?{'Content-Type':'application/json'}:{}),Prefer:'return=representation'},...(body?{body:JSON.stringify(body)}:{})});return {status:r.status,data:await r.json().catch(()=>null)}}
async function login(kind){const r=await call('/auth/v1/token?grant_type=password',null,{method:'POST',body:{email:`shopdesk-qa-${kind}-20261026@example.invalid`,password}});assert.equal(r.status,200,JSON.stringify(r.data));sessions.push(r.data.access_token);userIds[kind]=r.data.user.id;return r.data.access_token}
const [admin,customer,other]=await Promise.all(['admin','customer','other'].map(login));checks+=3;
assert.equal((await call('/rest/v1/products',null)).status,401);checks++;
let r=await call('/rest/v1/products',admin,{method:'POST',body:{name:'QA Integration Pen',category:'QA',description:'Disposable integration fixture',price:25,stock_quantity:3}});assert.equal(r.status,201,JSON.stringify(r.data));const id=r.data[0].id;checks++;
r=await call(`/rest/v1/products?id=eq.${id}`,admin,{method:'PATCH',body:{price:30}});assert.equal(r.data[0].price,30);checks++;
r=await call(`/rest/v1/products?id=eq.${id}`,customer,{method:'PATCH',body:{price:1}});assert.deepEqual(r.data,[]);checks++;
r=await call('/rest/v1/shop_admins',customer,{method:'POST',body:{user_id:userIds.customer}});assert.equal(r.status,403);checks++;
const key=randomUUID(),payload={p_items:[{product_id:id,quantity:2}],p_checkout_key:key};
r=await call('/rest/v1/rpc/checkout_shop',customer,{method:'POST',body:{...payload,p_items:[{product_id:id,quantity:2,price:1}]}});assert.equal(r.status,400);checks++;
r=await call('/rest/v1/rpc/checkout_shop',customer,{method:'POST',body:payload});assert.equal(r.status,200,JSON.stringify(r.data));assert.equal(r.data.total_amount,60);const orderId=r.data.order_id;checks++;
const retried=await call('/rest/v1/rpc/checkout_shop',customer,{method:'POST',body:payload});assert.deepEqual(retried.data,r.data);checks++;
r=await call(`/rest/v1/orders?id=eq.${orderId}&select=*,order_items(*)`,customer);assert.equal(r.data[0].order_items[0].subtotal,60);checks++;
r=await call(`/rest/v1/orders?id=eq.${orderId}`,other);assert.deepEqual(r.data,[]);checks++;
// Two real concurrent HTTP requests compete for the final unit.
const competing=await Promise.all([customer,other].map(token=>call('/rest/v1/rpc/checkout_shop',token,{method:'POST',body:{p_items:[{product_id:id,quantity:1}],p_checkout_key:randomUUID()}})));
assert.equal(competing.filter(r=>r.status===200).length,1);checks++;
r=await call(`/rest/v1/products?id=eq.${id}`,customer);assert.equal(r.data[0].stock_quantity,0);checks++;
r=await call(`/rest/v1/products?id=eq.${id}`,admin,{method:'DELETE'});assert.equal(r.data.length,1);checks++;
r=await call(`/rest/v1/order_items?order_id=eq.${orderId}`,customer);assert.equal(r.data[0].product_name,'QA Integration Pen');assert.equal(r.data[0].product_id,null);checks++;
console.log(`${checks} LIVE HTTP/Auth/RLS/checkout checks passed; concurrent checkout sold the last unit exactly once.`);
// Exercise actual UI event handlers in a DOM test environment against the live API.
const {JSDOM}=await import('/tmp/shopdesk-dbtest/node_modules/jsdom/lib/api.js');
const dom=new JSDOM('<div id="app"></div><div id="toast"></div><dialog id="modal"></dialog>',{url:'https://shopdesk-college-261026.wavytide128.chatgpt.site',runScripts:'dangerously'});const w=dom.window;w.fetch=fetch;w.structuredClone=structuredClone;w.scrollTo=()=>{};w.HTMLDialogElement.prototype.showModal=function(){this.open=true};w.HTMLDialogElement.prototype.close=function(){this.open=false};
w.eval((await Promise.all(['config.js','app.js','backend.js'].map(f=>fs.readFile('dist/'+f,'utf8')))).join('\n'));
async function until(predicate){const start=Date.now();while(!predicate()){if(Date.now()-start>20000)throw new Error('UI timeout: '+w.document.body.textContent.slice(-1200));await new Promise(r=>setTimeout(r,50))}}
async function uiLogin(kind){w.login(kind==='admin'?'admin':'customer');const f=w.document.getElementById('authform');f.elements.email.value=`shopdesk-qa-${kind}-20261026@example.invalid`;f.elements.password.value=password;f.dispatchEvent(new w.Event('submit',{cancelable:true}));await until(()=>!w.document.getElementById('modal').open);}
await uiLogin('admin');w.editProduct();const form=w.document.querySelector('#modal form');form.elements.name.value='QA UI Product';form.elements.category.value='QA';form.elements.price.value='19';form.elements.stock.value='2';form.elements.description.value='Disposable UI test fixture';form.dispatchEvent(new w.Event('submit',{cancelable:true}));await until(()=>!w.document.getElementById('modal').open);w.go('products');await until(()=>w.document.body.textContent.includes('QA UI Product'));
const uiId=(await call('/rest/v1/products?name=eq.QA%20UI%20Product',admin)).data[0].id;
w.document.querySelector('.sidebar > button.nav').click();await until(()=>w.document.body.textContent.includes('Customer Login'));
await uiLogin('customer');w.addCart(uiId);w.go('checkout');const checkout=w.document.getElementById('checkoutform');checkout.elements.customer.value='QA Customer';checkout.dispatchEvent(new w.Event('submit',{cancelable:true}));await until(()=>w.document.body.textContent.includes('Order confirmed'));assert.ok(w.document.body.textContent.includes('₹19.00'));
console.log('LIVE DOM UI flow passed: admin add product → customer sign-in → cart → checkout → saved receipt.');
await call(`/rest/v1/products?id=eq.${uiId}`,admin,{method:'DELETE'});
for(const token of sessions)await call('/auth/v1/logout',token,{method:'POST'});
w.close();process.exit(0);
