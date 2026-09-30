// Rename a merchant, then refuse to commit if the name no longer fits.
doc.override('banking-home/transactions-section/t1/info/merchant', {
  content: 'Apple Store, Fifth Avenue, New York'
});
const clipped = doc.tree('banking-home/transactions-section/t1', { expand: true })
  .filter(r => r.clip !== 'none');
if (clipped.length) {
  const r = clipped[0];
  throw new Error(`${r.name} is ${r.rect.width}pt wide and clips its row`);
}
