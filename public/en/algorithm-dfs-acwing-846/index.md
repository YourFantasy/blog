# Maximum Size of Connected Components


## Problem Description
Given a tree with n nodes (numbered 1 to n) and n-1 undirected edges. 

Please find the centroid of the tree and output the maximum number of nodes in each remaining connected component after removing the centroid.

Centroid Definition: The centroid of a tree is a node such that if it is removed, the maximum number of nodes in each remaining connected component is minimized.

## Input Format
The first line contains an integer n, representing the number of nodes in the tree.

The next n-1 lines contain two integers a and b each, representing an edge between nodes a and b.

## Output Format
Output an integer m, representing the maximum number of nodes in each remaining connected component after removing the centroid.

## Constraints
1 ≤ n ≤ 105

```markdown
Sample Input:
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

## Approach

## Code Implementation
### Code 1

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

// add1 constructs the graph
// son: stores the child nodes for each node with key k
// used: tracks whether node b has been used as a child node of any node
// Since a node can only be a child node of one node, if node b was a child node before, then at this moment, node b is the parent node of node a, and node a is the child node of node b
func add1(son map[int]*listNode, used []bool, a, b int) {
	if !used[b] {
		newNode := &listNode{val: b, next: son[a]}
		son[a] = newNode
		used[b] = true
	} else {
		newNode := &listNode

{val: a, next: son[b]}
		son[b] = newNode
	}
}

type listNode struct {
	val  int
	next *listNode
}

```

### Code 2

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

// Build the connection graph
// Reference: https://www.acwing.com/file_system/file/content/whole/index/content/4446359/
func add2(h, c, ne []int, p, s int, idx *int) {
	c[*idx] = s
	ne[*idx] = h[p]
	h[p] = *idx
	*idx += 1
}

```
