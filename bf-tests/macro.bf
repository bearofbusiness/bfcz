

;copies a to b using c as temp using offsets from current
mac cpy(a b c){
  >a[-<a>c+<c>b+<b>a]<a>c[-<c>a+<a>c]
}


>++<!cpy(1 0 2)
