#import "@preview/touying:0.7.0": *
#import themes.simple: *

#let note(content) = block(
  fill: silver.lighten(80%),
  stroke: (left: 4pt + silver),
  inset: 25pt,
  width: 100%,
  radius: (right: 4pt),
  content
)

#show: simple-theme.with(
  aspect-ratio: "16-9",
  footer: [Αξιόπιστα Συστήματα],
)

#title-slide[
  = μFork
  #v(2em)

  Supporting POSIX `fork` Within a Single-Address-Space Operating
  System.
]

== What's a SASOS?

// They were introduced in the 1990s following the advent of 64-bit
// addressing computers.

- The kernel and *all* user-space applications share one single
  massive address space. Virtual addresses are made unique.
  *Why?* #pause

  - *Lightweightness*: Context switches are instantaneous, TLB flushing
    is practically eliminated. #pause IPC is _fast_ (no kernel copy). #pause

  - *#text(fill: red)[Key Obstacle]*: _Inherently_ incompatible with
    `fork`. #pause

Security?

== Why's `fork` Important Anyways?

#pause

Turns out that *around half* of the 50 most popular C repositories on
GitHub and around half of the 50 most popular Debian packages use
`fork`. #pause

- `fork` for sub-process execution (bash) #pause
- `fork` for concurrency (nginx, apache) #pause
- `fork` for privilege separation (OpenSSH, qmail) #pause
- `fork` for on-demand resource duplication (redis snapshots)

== Implementation Challenges

#pause

- POSIX processes are isolated by virtue of residing in different
  address spaces. We must provide an equally secure workaround. #pause

- A SASOS `fork` must relocate the child to a _separate_, distinct
  virtual address region.  We must *relocate absolute memory
  references*, so that they too point within the child. #pause Pointer
  tracking is notoriously difficult (integer misidentification).
  #pause Must keep this transparent!

== Past Solutions

#pause

- Segment-Relative Addressing: Fast but gets messy when handwritten
  assembly, JIT runtimes and compiler integration are taken into
  account. (considerable engineering effort across the entire
  development toolchain) #pause

- OS as a Process: Treat SASOS as a process and implement `fork` for
  the hypervisor. Circumvents most challenges. Clever, _slow_ in
  practice (misses the entire point).

== Overview of μFork

#slide[
  #set align(center)
  #image("vas.svg", width: 60%)
]

We'll leverage position-independent code (PIC) so that the majority of
compiled memory references are made to be relative to the stack, base,
or instruction pointers. #pause

Crucially, Copy-on-Write must be *revisited*. We mustn't give read
access to pages containing stale absolute parent addresses. We'll
enforce *CoPA* (Copy-on-Pointer-Access). #pause

Now what? Who'll impose isolation? What about pointer tracking? #pause \
#h(1em) $->$ *hardware*

== CHERI 🍒

// Capabilities are initialized at boot by the operating system.

Elegant hardware technology designed to eliminate the majority of
memory safety bugs in RISC processors. #pause

- Pointers shall no longer be stored as raw integers (root of all
  evil). They're wrapped around *hardware-enforced _types_* called
  _capabilities_ along with relevant metadata (tag bit integrity).

```asm
lw s0, 8(a1)
# CHERI Version: Registers are extended
clw	s0, 8(ca1)
```

#empty-slide[
  #set align(center)
  #image("cheri.svg", width: 70%)
]

CHERI capabilities respect _monotonicity_. #pause The hardware
provides an almighty capability which is stripped down by the kernel
at will. #pause Isolation is guaranteed by the simple fact that
capability transformations can only ever _reduce_ privileges. #pause
Relative references? Not a problem. #pause

- Principle of Least Privilege
- Principle of Intentional Use

== Process-Kernel Isolation

Capabilities include an _object type_ field. A nonzero value indicates
a *sealed capability*. #pause The kernel can essentially form armored
system call entry point references (tokens) that can be called
(`cinvoke`), duplicated and moved around user-space programs
relentlessly. #pause Crucially, these capabilities _cannot_ be
modified by anyone except the sealer. #pause

$->$ The SASOS is, once more, blazingly (🤢) fast.

== Process-Kernel Isolation (Cont.)

#note[
  We implicitly refer to the Unikraft implementation.
]

#pause Privileged instructions are safely prohibited
(`access_system_registers` permission bit enforced on PPC). #pause
Everyone gets `EL1`! System calls are trivialized to external
procedures.

== Patching it Up

- *ASLR*? #pause Randomize the base offset of the contiguous process
  segment #pause

- *Heap*? #pause VAS is massive, assume a safe upper-bound. #pause

- *SMP*? #pause Big kernel lock (WIP :P). #pause

- *Fragmentation*? #pause Ignore (consider compaction)

== Clarifying CoPA

// CHERI capabilities can either reside in capability-aligned memory
// locations or in registers. The tag bit is present regardless
// (perhaps a headache for implementers).

// When forking for the first time, *register* capabilities are
// spontaneously relocated.

Exploit the CHERI page-table capability-was-accessed bit. #pause

- The child page table entry is forced to point to a free physical
  page and remains inaccessible until the copying has finished
  (atomicity). #pause

- The page is copied. #pause

- The page is scanned in 16-byte increments (size of CHERI
  capability). Absolute memory references are identified by the
  presence of a valid CHERI tag and are transformed accordingly, in
  place.

// GOT must be proactively copied because the address space is no
// longer identical.

== Overview

(verbal)

== Evaluation (Setup)

CHERI introduces a non-negligible overhead, so we'll compare μFork +
Unikraft with *CheriBSD*, a monolithic FreeBSD kernel running on the
Morello platform. μFork executes on top of the `bhyve` hypervisor
(missing drivers) but nevertheless *outperforms all competition*. #pause

Comparison with Nephele is unnecessary, it _will_ be slower. Nephele
is designed for `x86_64` only, so experimental data is directly
extracted from their (possibly biased) paper. They still lose.

#empty-slide[
  #set align(center)
  #image("bench_two.svg", width: 90%)
]
