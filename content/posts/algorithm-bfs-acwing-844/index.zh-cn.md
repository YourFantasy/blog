---
weight: 4
title: "迷宫最小的移动次数"
date: 2023-06-24T12:57:40+08:00
lastmod: 2023-06-24T14:57:40+08:00
draft: false
author: "Bard"
description: "bfs解决最短路问题"
images: []
resources:

tags: ["algorithm","bfs"]
categories: ["technology"]

lightgallery: true
---



## 题目描述
给定一个 n×m 的二维整数数组，用来表示一个迷宫，数组中只包含 0 或 1，其中 0 表示可以走的路，1 表示不可通过的墙壁。

最初，有一个人位于左上角 (1,1) 处，已知该人每次可以向上、下、左、右任意一个方向移动一个位置。

请问，该人从左上角移动至右下角 (n,m) 处，至少需要移动多少次。

数据保证 (1,1) 处和 (n,m) 处的数字为 0，且一定至少存在一条通路。

输入格式
第一行包含两个整数 n 和 m。

接下来 n 行，每行包含 m 个整数（0 或 1），表示完整的二维数组迷宫。

输出格式
输出一个整数，表示从左上角移动至右下角的最少移动次数。

数据范围
1≤n,m≤100
输入样例：
5 5
0 1 0 0 0
0 1 0 1 0
0 0 0 0 0
0 1 1 1 0
0 0 0 1 0
输出样例：
8

## 实现思路

典型的最短路问题，遍历从起始到终点的路径，记录最小值。

## 代码实现

```go
package main

import "fmt"

const N = 101

func main() {
	var n, m int
	fmt.Scanf("%d%d", &n, &m)
	nums := make([][]int, n)
	d := make([][]int, n)
	for i := 0; i < n; i++ {
		nums[i] = make([]int, m)
		d[i] = make([]int, m)
		for j := 0; j < m; j++ {
			var tmp int
			fmt.Scanf("%d", &tmp)
			nums[i][j] = tmp
			d[i][j] = -1
		}
	}
	fmt.Println(bfs(nums, d, newQueue(N*N)))
}

func bfs(nums, d [][]int, q *queue) int {
	n, m := len(nums), len(nums[0])
	d[0][0] = 0
	dx := [4]int{-1, 0, 1, 0}
	dy := [4]int{0, 1, 0, -1}
	q.push(&pair{0, 0})
	for !q.isEmpty() {
		t := q.pop()
		for i := 0; i < 4; i++ {
			// 上下左右四个方向寻找
			x, y := t.x+dx[i], t.y+dy[i] // 当前位置的下一个位置
			if x >= 0 && x < n && y >= 0 && y < m && nums[x][y] == 0 && d[x][y] == -1 {
				d[x][y] = d[t.x][t.y] + 1
				q.push(&pair{x, y})
			}
		}
	}
	return d[n-1][m-1]
}

type pair struct {
	x int
	y int
}

type queue struct {
	elements []*pair
	begin    int
	end      int
}

func newQueue(n int) *queue {
	return &queue{
		elements: make([]*pair, n),
		begin:    0,
		end:      -1,
	}
}

func (q *queue) push(p *pair) {
	q.end += 1
	q.elements[q.end] = p
}

func (q *queue) pop() *pair {
	res := q.elements[q.begin]
	q.elements[q.begin] = nil
	q.begin += 1
	return res
}

func (q *queue) isEmpty() bool {
	return q.end < q.begin
}
```