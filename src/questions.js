export const categories = ['Love & Romance','Childhood & Nostalgia','Psychology & Personality','Dreams & Ambitions','Philosophy & Life','Vulnerability & Deep Talks','Random & Ridiculous','Travel & Adventures','Art, Music & Literature','Us & Our Future','What If?','Secrets & Confessions','Surprise Me'];
export const questions = {
'Love & Romance':['What small gesture makes you feel most loved?','What does a perfect, ordinary day together look like?','When do you feel closest to someone you love?','What kind of affection means the most to you?','What song feels like the soundtrack to falling in love?','What is one little thing a partner can do to make a hard day softer?'],
'Childhood & Nostalgia':['What smell takes you straight back to childhood?','What did your happiest childhood afternoon look like?','Which childhood tradition would you bring back?'],
'Psychology & Personality':['What part of your personality took you longest to appreciate?','When do you feel most like yourself?','How do you usually show someone you trust them?'],
'Dreams & Ambitions':['What would you try if you knew you could not fail?','What does success feel like to you, beyond work?','What dream have you carried since you were young?'],
'Philosophy & Life':['What do you think makes a life feel well lived?','What belief have you changed your mind about?','Would you rather have more time or more courage?'],
'Vulnerability & Deep Talks':['What is something you wish people asked you about more?','When is it hardest for you to ask for help?','What helps you feel safe enough to be vulnerable?'],
'Random & Ridiculous':['If our relationship had a mascot, what would it be?','Which of us would survive longer in a zombie movie, and why?','What completely useless talent would you love to master?'],
'Travel & Adventures':['Which place would you love to experience together?','Are you happiest with a plan or a little beautiful chaos?','What is a travel moment you still think about?'],
'Art, Music & Literature':['Which book, film, or song changed how you see something?','What kind of art makes you feel understood?','If our story were a film, what would its title be?'],
'Us & Our Future':['What tiny ritual would you like us to make our own?','What would our ideal home feel like?','What are you most excited to experience together?'],
'What If?':['If we could live anywhere for one year, where would we go?','If we could relive one day together, which would you pick?','If we had a completely free weekend, what would we do?'],
'Secrets & Confessions':['What is a harmless secret talent you have?','What is something you were nervous to tell me at first?','What compliment have you never forgotten?']
};
export function pickQuestion(category, used=[]){const pool=questions[category]||Object.values(questions).flat(); const available=pool.filter(q=>!used.includes(q)); return (available.length?available:pool)[Math.floor(Math.random()*(available.length||pool.length))]}
