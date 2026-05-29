let _container = null;
let _homeRenderFn = null;

export function initNav(container, homeRenderFn) {
  _container = container;
  _homeRenderFn = homeRenderFn;
}

export function navigate(renderFn) {
  renderFn(_container);
}

export function goHome() {
  if (_homeRenderFn) _homeRenderFn(_container);
}
