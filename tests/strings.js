var s = 'hello world!';
for (var i = 0; i < s.length; i++) {
  console.log(s.charCodeAt(i));
}

for (var i = 0; i < s.length; i++) {
  for (var j = 0; j < s.length; j++) {
    console.log(s.slice(i, j));
  }
}

for (var i = 0; i < 10; i++) {
  console.log(String.fromCharCode(97 + i));
}

for (var i = 0; i < 26; i++) {
  console.log('aeiou'.indexOf(String.fromCharCode(97 + i)));
}
