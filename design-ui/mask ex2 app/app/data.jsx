// Sample voice names — 8-char ASCII, evocative of synth presets.
// Mix of bass, leads, pads, keys, sfx — feels like a real factory bank.

const FACTORY_VOICES = [
  ['001', 'MEGAMASK', 'LD'],  ['002', 'DAWNLITE', 'PD'],  ['003', 'LSOV    ', 'BS'],
  ['004', 'JTHROB  ', 'BS'],  ['005', 'BLADEKIC', 'PR'],  ['006', 'EDGEFALL', 'LD'],
  ['007', 'DX SOUL ', 'KY'],  ['008', 'MRJUKEBX', 'KY'],  ['009', 'MONOLEAD', 'LD'],
  ['010', 'SOLOBASS', 'BS'],  ['011', 'PURRLEAD', 'LD'],  ['012', 'FRETLESS', 'BS'],
  ['013', 'LQLVPAD ', 'PD'],  ['014', 'JFLUDE  ', 'KY'],  ['015', 'SPARKLE7', 'PD'],
  ['016', 'SLOOOWLY', 'PD'],  ['017', 'JEIGHTIE', 'KY'],  ['018', 'BENDPIPE', 'LD'],
  ['019', 'CHORDPLY', 'KY'],  ['020', 'DRYWELL ', 'PD'],  ['021', 'EVENTIDE', 'FX'],
  ['022', 'GLASSARP', 'AR'],  ['023', 'HOLOGRAM', 'PD'],  ['024', 'IRONFOOT', 'BS'],
  ['025', 'JUMPGATE', 'FX'],  ['026', 'KICKDRUM', 'PR'],  ['027', 'LATESHOW', 'KY'],
  ['028', 'MOONBEAM', 'PD'],  ['029', 'NIGHTOWL', 'LD'],  ['030', 'OCEANRUN', 'PD'],
  ['031', 'PIPEORG ', 'KY'],  ['032', 'QUARTZX ', 'LD'],  ['033', 'RAINFALL', 'PD'],
  ['034', 'SAWBLADE', 'LD'],  ['035', 'TUNDRAFM', 'PD'],  ['036', 'UNDERTOW', 'BS'],
  ['037', 'VAULTSUB', 'BS'],  ['038', 'WIRESPRK', 'FX'],  ['039', 'XOVERPLZ', 'LD'],
  ['040', 'YESBASIC', 'KY'],  ['041', 'ZENITHPD', 'PD'],  ['042', 'ARCADE88', 'LD'],
  ['043', 'BRASSEC ', 'KY'],  ['044', 'CRYSTALZ', 'PD'],  ['045', 'DEEPDIVE', 'BS'],
  ['046', 'EMBERFAL', 'PD'],  ['047', 'FOGHORN ', 'BS'],  ['048', 'GRANULAR', 'FX'],
];

const USER_VOICES = [
  ['001', 'MYBASS01', 'BS', false], ['002', 'PADTHING', 'PD', true],  ['003', 'LEADRC2 ', 'LD', false],
  ['004', 'KICKER  ', 'PR', false], ['005', 'WONKYARP', 'AR', true],  ['006', 'JTHROB  ', 'BS', false],
  ['007', 'SLABKEYS', 'KY', false], ['008', 'BSCRUNCH', 'BS', true],  ['009', 'OVERDOSE', 'LD', false],
  ['010', 'LSOV    ', 'BS', false], ['011', 'NIGHTSKY', 'PD', false], ['012', 'TAPEDLY ', 'FX', false],
  ['013', 'GLASSY1 ', 'PD', true],  ['014', 'PUMPLEAD', 'LD', false], ['015', 'EVENTIDE', 'FX', false],
  ['016', 'FRETLESS', 'BS', false], ['017', 'CHURCHRG', 'KY', false], ['018', 'WOOOOWAH', 'LD', true],
  ['019', 'LFOFEAR ', 'PD', false], ['020', 'PADTHING', 'PD', false], ['021', 'STRINGUH', 'KY', false],
  ['022', 'SUBSHAKR', 'BS', false], ['023', 'TRACKR  ', 'PR', false], ['024', 'GHOSTLI ', 'PD', true],
];

window.FACTORY_VOICES = FACTORY_VOICES;
window.USER_VOICES = USER_VOICES;
