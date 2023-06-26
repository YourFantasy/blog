weight: 4
title: "Maximum Size of Connected Components"
date: 2023-06-24T12:57:40+08:00
lastmod: 2023-06-24T14:57:40+08:00
draft: false
author: "Bard"
description: "Solving connected components problem using Depth-First Search"
images: []
resources:

tags: ["algorithm","bfs"]
categories: ["technology"]

lightgallery: true

## Problem Description

Given an n×m 2D integer array representing a maze, where the array contains only 0s and 1s, with 0 representing a path that can be traversed and 1 representing an impassable wall.

Initially, there is a person at the top-left corner (1, 1). It is known that the person can move one position in any direction: up, down, left, or right.

The task is to determine the minimum number of moves required for the person to reach the bottom-right corner (n, m).

It is guaranteed that the numbers at the top-left corner (1, 1) and the bottom-right corner (n, m) are both 0, and there is at least one valid path.

Input Format
The first line contains two integers, n and m.

The next n lines contain m integers (0 or 1), representing the complete 2D array maze.

Output Format
Print a single integer, representing the minimum number of moves required to reach the bottom-right corner from the top-left corner.

Constraints
1 ≤ n, m ≤ 100

```markdown
Input Example:
5 5
0 1 0 0 0
0 1 0 1 0
0 0 0 0 0
0 1 1 1 0
0 0 0 1 0
Output Example:
8
```

## Approach

This is a typical shortest path problem. We can use breadth-first search (BFS) to traverse the path from the start to the end, while keeping track of the minimum number of moves.

## Code Implementation

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
			// Check four directions: up, down, left, right
			x, y := t.x+dx[i], t.y+dy[i] // Next position from the current position
			if x >= 0 && x < n && y

 >= 0 && y < m && nums[x][y] == 0 && d[x][y] == -1 {
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