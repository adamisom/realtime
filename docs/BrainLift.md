# BrainLift: Real-Time Collaborative Music Games for Elementary Classrooms

## Owners

- Adam Isom

## Special Note on Relation of the Code Project to This BrainLift

This BrainLift was originally developed to guide a larger project that would have culminated in building the real-time collaborative music games described here. I completed significant backend work—a comprehensive Music Extension for Supabase Realtime—to validate the technical feasibility of low-latency, classroom-scale synchronization, but had to abandon the project due to shifting priorities. This document represents the pedagogical and market research foundation that informed that technical work.

The Music Extension I built includes drift-free tempo synchronization across 20+ participants, structured game state management for all five proposed games (Rhythm Circle, Melody Builder, Dynamics Dance, Improvisation Jam, Call and Response), teacher controls with role-based authorization, SEL data collection with participation tracking and student reflections, turn management, pattern matching for accuracy scoring, real-time analytics, and multi-tenant support with rate limiting.

Beyond music education, the generic infrastructure components——drift-free periodic event synchronization, turn management, pattern matching, flexible game state storage, sliding window rate limiting, multi-tenant process registry, real-time analytics aggregation, and event tracking——could support other real-time collaborative applications such as multiplayer educational games, live classroom activities with teacher controls, collaborative creative tools requiring state synchronization, or any structured real-time performance application. The technical patterns for managing classroom-scale real-time interaction are generalizable, even if this particular application remains unbuilt.

## Purpose

This BrainLift establishes a research-backed foundation for building real-time, classroom-scale collaborative music games. We focus on **facilitating measurable learning outcomes**—both musical and beyond—and identify a clear market opportunity where proven pedagogy meets a notable technological gap.

### In Scope

- Pedagogical requirements for real-time, synchronous music collaboration at classroom scale (20+ students).
- The integration of Social-Emotional Learning (SEL) and transferable cognitive skills as primary, measurable outcomes to meet market demand.
- Analysis of the specific market gap for tools that combine real-time performance, teacher controls, and structured pedagogical activities.
- Developmental appropriateness for elementary students (ages 7-11).

### Out of Scope

- Specific technical implementation details, monetization models, or marketing strategies.
- Individual (non-collaborative) music learning tools or advanced music theory instruction.
- Use cases outside of the elementary general music classroom.

---

## Spiky Points of View (SPOVs)

### SPOV 1: Real-time synchronous collaboration is not a feature—it is a pedagogical necessity for developing ensemble musicianship, grounded in the learning science principle of immediate feedback.

**Elaboration:** Current tools (such as Soundtrap and BandLab), while sophisticated, are designed for asynchronous composition and older students. They enable students to layer tracks independently, but this workflow cannot develop the real-time listening and responding skills central to ensemble performance. The core skills of ensemble musicianship—adapting dynamics, and developing shared musical intuition—require the **immediate feedback loops** that only synchronous (real-time) interaction can provide. Learning science demonstrates that immediate feedback accelerates skill acquisition, allowing students to adjust in the moment rather than after the fact. Research confirms that active, collaborative music-making has a significant positive effect on learning outcomes [1]. The widespread popularity of Chrome Music Lab's "Shared Piano" demonstrates latent demand for this kind of interaction [2], yet teachers found that without pedagogical structure, it required "a lot of support to lead to deep learning" [2], proving that technical feasibility alone is insufficient. The market gap is not due to a lack of need, but to the technical challenges of low-latency (minimal delay) audio synchronization, a problem that video conferencing tools have failed to solve for music [10]. By prioritizing technical convenience, the market has ignored the fundamental pedagogical need for real-time ensemble practice.

### SPOV 2: Integrating SEL and transferable cognitive skills is not an educational ideal; it is a core market demand with a proven ROI that current music ed-tech completely ignores.

**Elaboration:** For parents and schools, music education is valued not just for musical skill, but for its proven ability to develop transferable competencies. Research shows that music training improves **executive function** (working memory, inhibitory control) and that ensemble practice specifically develops the skills of teamwork and collaborative learning that are critical in other domains [7]. These benefits are directly aligned with the goals of Social-Emotional Learning (SEL), which has become a major priority for schools (with $87 million in federal grants allocated in FY2024 for SEL innovations alone). Students in SEL programs show an average **11 percentile-point gain in academic achievement** and see long-term benefits in graduation rates and employment, translating to an **$11 ROI for every $1 invested** [6]. Yet, the entire music ed-tech market is focused on narrow skill acquisition, leaving this funded, high-demand need unserved. A product that makes these transferable skills and SEL outcomes visible and measurable doesn't just serve a pedagogical goal; it meets a clear market need and provides a powerful competitive differentiator.

### SPOV 3: The greatest unmet need is not in small-group tools, but in software designed for the reality of the elementary music classroom: whole-class (20+) instruction.

**Elaboration:** While most collaboration software is built for small groups, the reality of elementary music education is whole-class instruction. A tool designed for a quartet is not suited for a typical classroom of 25 students. To be effective, a classroom-scale tool should be built with the teacher as the central facilitator. This requires a specific suite of pedagogical controls: the ability to mute/unmute students to focus listening, control tempo, and see real-time data on student participation [8]. The opportunity is not to replace the teacher, but to empower them with a tool that enables new forms of collaborative learning that are logistically impossible with traditional instruments alone.

---

## Proposed Music Games

Here are five initial game concepts designed to be simple, engaging, and pedagogically sound for elementary students.

| Game                | What It Is                                                                                               | Why It Matters (Pedagogy)                                                                                             | 
| ------------------- | -------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------- | 
| **1. Rhythm Circle**    | Students play a note in sequence to create a group rhythm pattern.                                       | Develops foundational rhythm skills, listening, and turn-taking.                                                      | 
| **2. Melody Builder**   | Each student is assigned a note in a scale; the teacher or a student conductor calls out a melody to play. | Teaches basic melody, scale structure, and the relationship between individual notes and a larger musical phrase.     | 
| **3. Dynamics Dance**   | Students play together while following visual cues to adjust their volume (loud, soft, medium).          | Introduces the concept of dynamics and expressive control, a key element of musicality.                               | 
| **4. Improvisation Jam** | Students freely play notes within a given scale over a backing track.                                    | Encourages creativity, self-expression, and exploration within a safe, structured environment.                        | 
| **5. Call and Response** | The teacher plays a short pattern, and students echo it back.                                            | Develops active listening, short-term musical memory, and imitation skills—foundational to all musical learning. | 

### Future Work: Differentiated Instruction

Once market fit is established with this initial suite of games, a natural next step is to build out a broader suite of tasks that allow teachers to assign different parts to different students based on their skill level. This would more fully realize the learning science principle of the **Zone of Proximal Development (ZPD)**, enabling true differentiated instruction within a collaborative, whole-class setting.

---

## Experts

- **Dr. Martina Vasil** (University of Kentucky): Leading researcher in collaborative music pedagogy and its connection to social justice and democratic participation. Her work provides the academic foundation for structuring collaborative games. [Google Scholar](https://scholar.google.com/citations?user=L8-22-IAAAAJ&hl=en)
- **NAFME** (National Association for Music Education): The leading U.S. professional organization for music educators. Their position statements on SEL and technology represent the consensus of the profession. [NAFME Website](https://nafme.org)
- **CASEL** (Collaborative for Academic, Social, and Emotional Learning): The definitive organization for SEL, providing the 5-competency framework and research on outcomes widely adopted by U.S. schools. [CASEL Framework](https://casel.org/fundamentals-of-sel/)
- **Dr. Peter Webster** (University of Southern California): A foundational expert in music education technology and creative thinking in music. His work informs how to assess creative musical learning. [USC Profile](https://music.usc.edu/peter-webster/)

---

## Knowledge Tree

### Category 1: Pedagogy & Tools

- **Source 1: Meta-Analysis - "Evidence-Based Music Teaching and Learning"**
  - **Facts:** Meta-analysis found a medium effect size (d = .56) for music teaching activities. Ensemble performance showed strong outcomes for both musical and social development. Active music-making is more effective than passive listening.
  - **Link:** https://www.sciencedirect.com/science/article/pii/S1747938X25000351

- **Source 2: Chrome Music Lab - Shared Piano**
  - **Facts:** A real-time collaborative piano tool with no educational scaffolding. It is one of CML's most popular experiments, demonstrating technical feasibility and market demand. The project was abandoned in 2021, leaving the gap unfilled.
  - **Link:** https://musiclab.chromeexperiments.com/Shared-Piano/

- **Source 3: Existing Tools Analysis - Soundtrap and BandLab**
  - **Facts:** These are asynchronous collaboration platforms focused on music production (layering tracks). They do not support real-time synchronous performance and thus cannot develop ensemble skills (the ability to listen and respond to others).
  - **Link:** https://www.soundtrap.com/edu/ and https://edu.bandlab.com/

### Category 2: Social-Emotional & Transferable Skills

- **Source 4: NAFME - "Music Education and Social-Emotional Learning"**
  - **Facts:** NAFME officially connects music education to all five CASEL competencies, including social awareness (listening to peers) and relationship skills (cooperation in an ensemble).
  - **Link:** https://nafme.org/blog/music-education-social-emotional-learning/

- **Source 5: CASEL Framework Documentation**
  - **Facts:** Defines the five core SEL competencies. Advocates for assessment using multiple measures, including self-report, teacher observation, and behavioral data.
  - **Link:** https://casel.org/fundamentals-of-sel/

- **Source 6: CASEL - "What Does the Research Say?"**
  - **Facts:** SEL programs improve academic performance by an average of 11 percentile points. Analysis of six evidence-based programs shows an $11 return for every $1 invested. Positive impacts on graduation rates and employment persist up to 18 years later.
  - **Link:** https://casel.org/fundamentals-of-sel/what-does-the-research-say/

- **Source 7: Ensemble Skills as Transferable Professional Attributes**
  - **Facts:** The skills of working in ensembles, including teamwork and collaborative learning, are increasingly understood to be critical and transferable professional attributes valued in higher education and other professional contexts.
  - **Link:** https://journals.sagepub.com/doi/10.1177/1474022219885791

### Category 3: Classroom & Technical Context

- **Source 8: Teacher Control Requirements for Classroom Music Technology**
  - **Facts:** For whole-class use, teachers require controls like mute/unmute, role assignment for differentiation, tempo control, and visibility into student participation. These are pedagogical necessities.
  - **Note:** Synthesis of established classroom management principles applied to music technology.

- **Source 9: Competitive Analysis - Music Ed-Tech Landscape**
  - **Facts:** The market is segmented into tools for individual learning, asynchronous collaboration, and unstructured real-time jamming. No tool combines real-time collaboration with classroom-scale management and pedagogical structure.
  - **Note:** Original market analysis.

- **Source 10: Technical Challenges of Real-Time Audio Synchronization**
  - **Facts:** Real-time music requires <100ms latency. Video conferencing tools have 150-300ms latency. The Web Audio API makes low latency possible, but synchronizing 20+ streams is a complex engineering challenge that most companies have avoided.
  - **Note:** Synthesis of real-time audio synchronization constraints for web platforms.

---

## References

[1] Nielsen, S. G., & Jørgensen, H. (2025). Evidence-Based Music Teaching and Learning. *International Encyclopedia of Education (Fourth Edition)*. https://www.sciencedirect.com/science/article/pii/S1747938X25000351

[2] Chrome Music Lab. (n.d.). *Shared Piano*. https://musiclab.chromeexperiments.com/Shared-Piano/

[3] Soundtrap for Education. (n.d.). https://www.soundtrap.com/edu/ | BandLab for Education. (n.d.). https://edu.bandlab.com/

[4] NAFME. (2019). *Music Education and Social-Emotional Learning*. https://nafme.org/blog/music-education-social-emotional-learning/

[5] CASEL. (n.d.). *Fundamentals of SEL*. https://casel.org/fundamentals-of-sel/

[6] CASEL. (n.d.). *What Does the Research Say?* https://casel.org/fundamentals-of-sel/what-does-the-research-say/

[7] Gaunt, H., & Treacy, D. S. (2020). Ensemble practices in the arts: A reflective matrix to enhance team work and collaborative learning in higher education. *Arts and Humanities in Higher Education*, 19(4), 422-442. https://journals.sagepub.com/doi/10.1177/1474022219885791

[8] Synthesis of established classroom management principles applied to music technology.

[9] Original competitive analysis of the music education technology landscape.

[10] Synthesis of real-time audio synchronization constraints for web platforms.
