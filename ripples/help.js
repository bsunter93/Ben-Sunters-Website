// Knock⌃On Ripple Map v6 (WS-D): the "How to read the map" dialog, loaded on the first tap of the ? button (ui.js chrome).
import * as L from './lib.js';
import { $, h, em, tt_, ls } from './ui.js';

export function help() {
  let d = $('#helpdlg');
  if (!d) {
    const hide = ls.get('ko.hide_middle') === '1';
    d = h('dialog', { id: 'helpdlg', 'aria-labelledby': 'helpt' },
      h('h2', { id: 'helpt', tabindex: '-1', autofocus: true }, 'How to read the Ripple Map'),
      h('p', null, 'Each upstream shock is a line. Each stop is a series in another part of life that moved against its own normal after the shock. We test many paths and show the ones that stayed flat too.'),
      h('h3', null, 'Tiers'),
      h('ul', null, ['measured', 'likely', 'watching', 'flat'].map(t => h('li', null, t === 'flat' ? h('b', { 'aria-hidden': 'true' }, '⊥') : tt_(t), h('span', null, h('b', null, L.TIER[t].w + '. '), L.TIER[t].def)))),
      h('h3', null, 'Two fluke numbers, never merged'),
      h('p', null, h('b', null, 'Lookalikes: '), '"A random pairing looks this strong about 1 in N times" compares the stop with fake dates, fake starts and fake pages.'),
      h('p', null, h('b', null, 'Fluke rate: '), '"Links like this turn out to be flukes about 1 in K times" comes from calm pages we run through the same tests every day (shown as 1 in 50+ past 50).'),
      h('h3', null, 'Domains'),
      h('ul', null, L.DOMAINS.map(k => h('li', null, em(L.DOM[k].i), h('span', null, h('b', null, L.DOM[k].w + ': '), L.DOM[k].d)))),
      h('label', { class: 'tog' }, h('input', { type: 'checkbox', checked: hide, onchange: e => { ls.set('ko.hide_middle', e.target.checked ? '1' : '0'); } }), 'Hide the middle stops until I open them'),
      h('p', { class: 'xs' }, h('a', { href: '/ripples/methods/', class: 'lnk' }, 'Methods and receipts')),
      h('form', { method: 'dialog' }, h('button', { class: 'btn sec' }, 'Got it')));
    document.body.append(d);
  }
  d.showModal();
}
