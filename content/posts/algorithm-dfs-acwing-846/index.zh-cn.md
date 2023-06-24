---
weight: 4
title: "连通块点数最大值"
date: 2023-06-24T12:57:40+08:00
lastmod: 2023-06-24T14:57:40+08:00
draft: false
author: "Bard"
description: "深度优先搜索解决连通块问题"
images: []
resources:

tags: ["algorithm","bfs"]
categories: ["technology"]

lightgallery: true
---

## 题目描述
给定一颗树，树中包含 n 个结点（编号 1∼n）和 n−1 条无向边。

请你找到树的重心，并输出将重心删除后，剩余各个连通块中点数的最大值。

重心定义：重心是指树中的一个结点，如果将这个点删除后，剩余各个连通块中点数的最大值最小，那么这个节点被称为树的重心。

输入格式
第一行包含整数 n，表示树的结点数。

接下来 n−1 行，每行包含两个整数 a 和 b，表示点 a 和点 b 之间存在一条边。

输出格式
输出一个整数 m，表示将重心删除后，剩余各个连通块中点数的最大值。

数据范围
1≤n≤105
```markdown
输入样例:
9
1 2
1 7
1 4
2 8
2 5
4 3
3 9
4 6
```

## 实现思路

## 代码实现
### 代码1

```go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)
func main() {
	var n int
	fmt.Scanf("%d", &n)
	son := make(map[int]*listNode)
	used := make([]bool, n+1)
	scanner := bufio.NewScanner(os.Stdin)
	buf := make([]byte, 2000*1000)
	scanner.Buffer(buf, len(buf))
	for i := 0; i < n-1; i++ {
		scanner.Scan()
		ss := strings.Split(scanner.Text(), " ")
		var a, b int
		a, _ = strconv.Atoi(ss[0])
		b, _ = strconv.Atoi(ss[1])
		add1(son, used, a, b)
	}
	res := n
	dfs1(son, n, 1, &res, make([]bool, n+1))
	fmt.Println(res)
}

func dfs1(mp map[int]*listNode, n, t int, res *int, visited []bool) int {
	visited[t] = true
	tmp := 0
	sum := 1
	for h := mp[t]; h != nil; h = h.next {
		if !visited[h.val] {
			s := dfs1(mp, n, h.val, res, visited)
			tmp = max(tmp, s)
			sum += s
		}
	}
	tmp = max(tmp, n-sum)
	*res = min(*res, tmp)
	return sum
}

func max(a, b int) int {
	if a < b {
		return b
	}
	return a
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

// add 构造图
// son，存储编号为k的节点的孩子节点
// used 编号为b的节点是否曾经是某个节点的孩子节点,是否被用作过孩子节点
// 因为同一个节点只能是一个节点的孩子节点，所以如果b节点之前为某个节点的孩子节点，那么此时b节点是a节点的父节点，a节点是b节点的孩子节点
func add1(son map[int]*listNode, used []bool, a, b int) {
	if !used[b] {
		newNode := &listNode{val: b, next: son[a]}
		son[a] = newNode
		used[b] = true
	} else {
		newNode := &listNode{val: a, next: son[b]}
		son[b] = newNode
	}
}

type listNode struct {
	val  int
	next *listNode
}

```

###	代码2

```go
package main

import (
	"bufio"
	"fmt"
	"os"
	"strconv"
	"strings"
)

func main() {
	var n int
	fmt.Scanf("%d", &n)
	h, c, ne := make([]int, n+1), make([]int, 2*n+1), make([]int, 2*n+1)
	for i := 0; i <= n; i++ {
		h[i] = -1
	}
	idx := 0
	visited := make([]bool, n+1)
	scanner := bufio.NewScanner(os.Stdin)
	buf := make([]byte, 20000*1000)
	scanner.Buffer(buf, len(buf))
	for i := 0; i < n-1; i++ {
		scanner.Scan()
		s := scanner.Text()
		ss := strings.Split(s, " ")
		var a, b int
		a, _ = strconv.Atoi(ss[0])
		b, _ = strconv.Atoi(ss[1])
		add2(h, c, ne, a, b, &idx)
		add2(h, c, ne, b, a, &idx)
	}
	res := n
	dfs2(h, c, ne, n, 1, visited, &res)
	fmt.Println(res)
}

func dfs2(h, c, ne []int, n, t int, visited []bool, res *int) int {
	visited[t] = true
	sum := 1
	tmp := 0
	for i := h[t]; i != -1; i = ne[i] {
		if !visited[c[i]] {
			s := dfs2(h, c, ne, n, c[i], visited, res)
			sum += s
			tmp = max(tmp, s)
		}
	}
	tmp = max(tmp, n-sum)
	*res = min(*res, tmp)
	return sum
}

// 建立连接图
// 参考https://www.acwing.com/file_system/file/content/whole/index/content/4446359/
func add2(h, c, ne []int, p, s int, idx *int) {
	c[*idx] = s
	ne[*idx] = h[p]
	h[p] = *idx
	*idx += 1
}

```