#import "common.typ" as cm
#show: cm.setup.with(page-title: "Dynamics and Relativity")

= Sheet 1

Problems and solutions of #link("https://davidtong.org/pdfs/teaching/dynamics-and-relativity/htl1.pdf")[this sheet] by David Tong (and his predecessors). In what follows we make use of SymPy as a CAS to help with the verification of the expansions and results.

```python
import sympy as sp
```

== Problem 1

In one spatial dimension, two frames of reference $S$ and $S^prime$ have coordinates $(x, t)$ and $(x^prime, t^prime)$ respectively. The coordinates are related by $t^prime = t$ and $x^prime = f(x, t)$. Viewed from frame $S$, a particle follows a trajectory $x = x(t)$. It has velocity $v = dot(x)$ and acceleration $a = dot.double(x)$. Viewed from $S^prime$, the trajectory is $x^prime = f(x(t), t)$. Using the chain rule, show that the speed and acceleration of the particle in $S^prime$ are given by

$
  // --
            cm.pdiff(x^prime, t^prime) & = v cm.pdiff(f, t) + cm.pdiff(f, "t") \
  // --
  cm.pdiff(x^prime, t^prime, order: 2) & = a cm.pdiff(f, x)
                                         + v^2 cm.pdiff(f, x, order: 2)
                                         + 2 v cm.pdiff(f, x t, order: 2)
                                         + cm.pdiff(f, t, order: 2)
$

Suppose now that both $S$ and $S^prime$ are inertial frames. Explain why the function $f$ must obey $cm.sfrac(partial^2 f, partial x^2) = cm.sfrac(partial^2 f, partial x partial t) = cm.sfrac(partial^2 f, partial t^2) = 0$. What is the most general form of $f$ with these properties? Interpet this result.

```python
t = sp.symbols("t")
x = sp.symbols("x", cls=sp.Function)(t)
f = sp.symbols("f", cls=sp.Function)(x, t)

f_st = f.diff(t)
f_nd = f_st.diff(t)
```

```python
f_st.doit()
```

```python
f_nd.doit().expand()
```

```python
v = sp.symbols("v", cls=sp.Function)(t)
a = sp.symbols("a", cls=sp.Function)(t)

v_def = x.diff(t)
a_def = v.diff(t)

f_st = f_st.subs(v_def, v)
f_nd = f_nd.subs(v_def, v).subs(a_def, a).expand()
```

```python
f_st
```

```python
f_nd
```

== Problem 2
