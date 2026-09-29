// Native Higgsedit composition. Illustrated demo, not a screen recording.
// Render with: higgsedit build autocorrect-demo.jsx
export default async ({ project }) => {
  const p = await project({ dir: "/home/user/autocorrect-demo", size: "1280x720", fps: 24, background: "#0B0E14" });
  const blue = "#6AA6FF", white = "#F3F5FA", muted = "#9CA7B9";
  const fade = [{property:"opacity",from:0,to:1,at:0,duration:0.25,easing:"ease-out"},
                {property:"offsetY",from:12,to:0,at:0,duration:0.4,easing:"ease-out"}];
  const title = (s, y=151) => <text x={120} y={y} width={1080} height={76} fontFamily="Inter" fontSize={52} fontWeight={700} color={white}>{s}</text>;
  const note = (s) => <text x={168} y={551} width={1000} height={48} fontFamily="Inter" fontSize={28} color={muted}>{s}</text>;
  const card = () => [
    <rect x={120} y={272} width={1040} height={244} radius={22} fill="#151B26" strokeColor="#2D394D" strokeWidth={1}/>,
    <rect x={146} y={295} width={9} height={9} radius={4.5} fill="#FC6862"/>,
    <rect x={165} y={295} width={9} height={9} radius={4.5} fill="#F3C058"/>,
    <rect x={184} y={295} width={9} height={9} radius={4.5} fill="#6BC889"/>,
    <text x={930} y={287} width={196} height={30} fontFamily="Inter" fontSize={17} color={muted} align="right">Example text field</text>
  ];
  const word = (s, at, dur, color=white) => <text x={166} y={358} width={1000} height={98} fontFamily="Inter" fontSize={64} fontWeight={400} color={color} at={at} duration={dur}>{s}</text>;
  p.compose([
    <rect x={64} y={49} width={47} height={47} radius={12} fill="#347CEB"/>,
    <text x={72} y={48} width={36} height={50} fontFamily="Inter" fontSize={29} fontWeight={700} color="#FFFFFF">a</text>,
    <path x={94} y={63} width={12} height={16} d="M 0 7 L 4 11 L 11 1" stroke={{color:"#FFFFFF",width:2.2,cap:"round"}}/>,
    <text x={127} y={56} width={540} height={42} fontFamily="Inter" fontSize={27} fontWeight={600} color={white}>AutoCorrect for Mac</text>,
    <text x={66} y={658} width={500} height={28} fontFamily="Inter" fontSize={17} color="#778399">Illustrated demo · Preview release</text>,
    <text x={694} y={658} width={520} height={28} fontFamily="Inter" fontSize={17} color="#778399" align="right">Local processing. Compatible text fields.</text>
  ], {at:0,dur:18,name:"Brand"});
  p.compose(<group width={1280} height={720} animate={fade}>
    <text x={120} y={221} width={1100} height={134} fontFamily="Inter" fontSize={104} fontWeight={700} color={white}>Keep typing.</text>
    <text x={124} y={372} width={1060} height={76} fontFamily="Inter" fontSize={40} color={blue}>A little help with every word.</text>
    <text x={124} y={482} width={1060} height={60} fontFamily="Inter" fontSize={26} color={muted}>Spelling and shortcuts, right from your menu bar.</text>
  </group>, {at:0,dur:2,name:"Intro"});
  p.compose(<frame width={1280} height={720} layout="none">{[title("A typo? Keep going."), ...card(),
    word("teh",0,0.8), word("teh ",0.8,0.4), word("the ",1.2,0.5,blue),
    word("the n",1.7,0.15), word("the ne",1.85,0.15), word("the nex",2,0.15), word("the next",2.15,1.85),
    <rect x={167} y={448} width={102} height={3} radius={1.5} fill={blue} at={1.2} duration={2.8}/>,
    note("Corrects when you finish the word.")
  ]}</frame>, {at:2,dur:4,name:"Spelling"});
  p.compose(<frame width={1280} height={720} layout="none">{[title("Less typing. Same meaning."), ...card(),
    word("i",0,0.25),word("id",0.25,0.25),word("idk",0.5,0.65),
    word("I don't know",1.15,2.85,blue),
    note("Built-in shortcuts. Add your own phrases.")
  ]}</frame>, {at:6,dur:4,name:"Shortcuts"});
  p.compose(<frame width={1280} height={720} layout="none">{[title("Your spelling gets the last word."), ...card(),
    word("homebred ",0,0.8),word("homebred",0.8,0.2),word("homebre",1,0.25),
    word("homebrew",1.25,0.4),word("homebrew ",1.65,2.35,blue),
    <text x={831} y={467} width={293} height={30} fontFamily="Inter" fontSize={20} color={blue} align="right" at={1.65} duration={2.35}>Your choice stays.</text>,
    note("Change a correction back. We leave that word alone.")
  ]}</frame>, {at:10,dur:4,name:"Manual choice"});
  p.compose(<group width={1280} height={720} animate={fade}>
    {title("Try AutoCorrect.",216)}
    <text x={124} y={316} width={1070} height={68} fontFamily="Inter" fontSize={32} color={muted}>Free and open source. Made for your Mac.</text>
    <rect x={120} y={421} width={1040} height={94} radius={16} fill="#172B47" strokeColor="#29466D" strokeWidth={1}/>
    <text x={148} y={447} width={1000} height={60} fontFamily="Inter" fontSize={31} fontWeight={600} color={blue}>github.com/markoderic/autocorrect</text>
    <text x={124} y={552} width={1060} height={44} fontFamily="Inter" fontSize={23} color={muted}>Download the app, or install with Homebrew.</text>
  </group>, {at:14,dur:4,name:"Get the app"});
  await p.frame(4.7, "/home/user/autocorrect-demo.png");
  await p.render("/home/user/autocorrect-demo.mp4", {depth:8,bitrate:3000000,concurrency:2});
};

