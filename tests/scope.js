var bar = 1;
var bat = 1;

function foo(bat) {
  var baz = 0;
  bar++;
  baz++;
  bat++;
  console.log(bar);
  console.log(baz);
  console.log(bat);
}

foo(0);
console.log(bar);
console.log(bat);
