var freeaps_determineBasal;(()=>{var e={2982:(e,t,a)=>{var r=a(3531);function n(e,t){t||(t=0);var a=Math.pow(10,t);return Math.round(e*a)/a}function o(e,t){return"mmol/L"===t.out_units?n(.0555*e,1):Math.round(e)}e.exports=function(e,t,a,i,s,l,u,m,d,c,g,h,p,v,B){var f=i.min_bg,b=v.overrideTarget;0!=b&&6!=b&&v.useOverride&&!i.temptargetSet&&(f=b),v.smbIsOff;const M=v.advancedSettings,_=v.isfAndCr,y=v.isf,x=v.cr,S=v.smbIsAlwaysOff;v.start,v.end;const D=v.smbMinutes,w=v.uamMinutes;var G=h.useNewFormula,C=0,T=f,U=new Date;c&&(U=new Date(c));var O=0,R="",A="",I="",F="",j="",P="",E=0,q=0,W=0,k=0,L=0,z=0;const N=v.weightedAverage;var H=1,Z=i.sens,$=i.carb_ratio;v.useOverride&&(H=v.overridePercentage/100,_?(Z/=H,$/=H):(x&&($/=H),y&&(Z/=H)));const J=i.weightPercentage,K=v.average_total_data;function Q(e,t){var a=e.getTime();return new Date(a+36e5*t)}function V(e){var t=i.bolus_increment;.1!=t&&(t=.05);var a=e/t;return a>=1?n(Math.floor(a)*t,5):0}function X(e){function t(e){return e<10&&(e="0"+e),e}return t(e.getHours())+":"+t(e.getMinutes())+":00"}function Y(e,t){var a=new Date("1/1/1999 "+e),r=new Date("1/1/1999 "+t);return(a.getTime()-r.getTime())/36e5}const ee=Math.min(i.autosens_min,i.autosens_max),te=Math.max(i.autosens_min,i.autosens_max);function ae(e,t){var a=0,r=t,n=(e-t)/36e5,o=0,i=n,s=0;do{if(n>0){var l=X(r),u=p[0].rate;for(let e=0;e<p.length;e++){var m=p[e].start;if(l==m){if(e+1<p.length)n>=(s=Y(p[e+1].start,p[e].start))?o=s:n<s&&(o=n);else if(e+1==p.length){let t=p[0].start;n>=(s=24-Y(p[e].start,t))?o=s:n<s&&(o=n)}a+=V((u=p[e].rate)*o),n-=o,console.log("Dynamic ratios log: scheduled insulin added: "+V(u*o)+" U. Bas duration: "+o.toPrecision(3)+" h. Base Rate: "+u+" U/h. Time :"+l),r=Q(r,o)}else if(l>m)if(e+1<p.length){var d=p[e+1].start;l<d&&(n>=(s=Y(d,l))?o=s:n<s&&(o=n),a+=V((u=p[e].rate)*o),n-=o,console.log("Dynamic ratios log: scheduled insulin added: "+V(u*o)+" U. Bas duration: "+o.toPrecision(3)+" h. Base Rate: "+u+" U/h. Time :"+l),r=Q(r,o))}else e==p.length-1&&(n>=(s=Y("23:59:59",l))?o=s:n<s&&(o=n),a+=V((u=p[e].rate)*o),n-=o,console.log("Dynamic ratios log: scheduled insulin added: "+V(u*o)+" U. Bas duration: "+o.toPrecision(3)+" h. Base Rate: "+u+" U/h. Time :"+l),r=Q(r,o))}}}while(n>0&&n<i);return a}if((te==ee||te<1||ee>1)&&(G=!1,console.log("Dynamic ISF disabled due to current autosens settings")),g.length){if(G){let e=g.length-1;var re=new Date(g[e].timestamp),ne=new Date(g[0].timestamp);"TempBasalDuration"==g[0]._type&&(ne=new Date),(O=(ne-re)/36e5)<23.9&&O>21?(L=ae(re,(oe=24-O,ie=re.getTime(),new Date(ie-36e5*oe))),F="24 hours of data is required for an accurate tdd calculation. Currently only "+O.toPrecision(3)+" hours of pump history data are available. Using your pump scheduled basals to fill in the missing hours. Scheduled basals added: "+L.toPrecision(5)+" U. "):O<21?(G=!1,enableDynamicCR=!1):F=""}}else console.log("Pumphistory is empty!"),G=!1,enableDynamicCR=!1;var oe,ie,se;if(G){for(let e=0;e<g.length;e++)"Bolus"==g[e]._type&&(k+=g[e].amount);for(let e=1;e<g.length;e++)if("TempBasal"==g[e]._type&&g[e].rate>0){E=e,z=g[e].rate;var le=g[e-1]["duration (min)"]/60,ue=le,me=new Date(g[e-1].timestamp),de=new Date(me),ce=0;do{if(e--,0==e){de=new Date;break}if("TempBasal"==g[e]._type||"PumpSuspend"==g[e]._type){de=new Date(g[e].timestamp);break}var ge=e-2;if(ge>=0&&"Rewind"==g[ge]._type){let e=g[ge].timestamp;for(;ge-1>=0&&"Prime"==g[ge-=1]._type;)ce=(g[ge].timestamp-e)/36e5;ce>=le&&(de=new Date(e),ce=0)}}while(e>0);var he=(de-me)/36e5;he<ue&&(le=he),W+=V(z*(le-ce)),e=E}for(let e=0;e<g.length;e++)if(0==g[e]["duration (min)"]||"PumpResume"==g[e]._type){let t=new Date(g[e].timestamp),a=new Date(t),r=e;do{if(r>0&&(--r,"TempBasal"==g[r]._type)){a=new Date(g[r].timestamp);break}}while(r>0);(a-t)/36e5>0&&(L+=ae(a,t))}for(let e=g.length-1;e>0;e--)if("TempBasalDuration"==g[e]._type){let t=g[e]["duration (min)"]/60,a=new Date(g[e].timestamp);var pe=new Date(a);let r=e;do{if(--r,r>=0&&("TempBasal"==g[r]._type||"PumpSuspend"==g[r]._type)){pe=new Date(g[r].timestamp);break}}while(r>0);0==e&&"TempBasalDuration"==g[0]._type&&(pe=new Date,t=g[e]["duration (min)"]/60),(pe-a)/36e5-t>0&&(L+=ae(pe,Q(a,t)))}var ve={TDD:n(q=k+W+L,5),bolus:n(k,5),temp_basal:n(W,5),scheduled_basal:n(L,5)};O>21?(A=". Bolus insulin: "+k.toPrecision(5)+" U",I=". Temporary basal insulin: "+W.toPrecision(5)+" U",R=". Insulin with scheduled basal rate: "+L.toPrecision(5)+" U",j=F+" TDD past 24h is: "+q.toPrecision(5)+" U"+A+I+R,P=", TDD: "+n(q,2)+" U, "+n(k/q*100,0)+"% Bolus "+n((W+L)/q*100,0)+"% Basal"):P=", TDD: Not enough pumpData (< 21h)"}const Be=e.glucose,fe=h.enableDynamicCR,be=h.adjustmentFactor,Me=h.adjustmentFactorSigmoid,_e=h.sigmoid,ye=f;var xe,Se=!1,De="",we=1;K>0&&(we=N/K),we>1?(we=n(we=Math.min(we,i.autosens_max),2),i.autosens_max):we<1&&(we=n(we=Math.max(we,i.autosens_min),2),i.autosens_min),xe=", Basal ratio: "+we,(i.high_temptarget_raises_sensitivity||i.exercise_mode||v.isEnabled)&&(Se=!0),ye>=118&&Se&&(G=!1,De="Dynamic ISF temporarily off due to a high temp target/exercising. Current min target: "+ye);var Ge=", Dynamic ratios log: ",Ce=", AF: "+(_e?Me:be),Te="BG: "+Be+" mg/dl ("+(.0555*Be).toPrecision(2)+" mmol/l)",Ue="",Oe="";const Re=h.curve,Ae=i.insulinPeakTime,Ie=h.useCustomPeakTime;var Fe=55,je=65;switch(Re){case"rapid-acting":je=65;break;case"ultra-rapid":je=50}Ie?(Fe=120-Ae,console.log("Custom insulinpeakTime set to :"+Ae+", insulinFactor: "+Fe)):(Fe=120-je,console.log("insulinFactor set to : "+Fe)),se=q,J<1&&N>0&&(q=N,console.log("Using weighted TDD average: "+n(q,2)+" U, instead of past 24 h ("+n(se,2)+" U), weight: "+J),Oe=", Weighted TDD: "+n(q,2)+" U");var Pe="";if(G)if(_e){const e=ee,t=te-e;var Ee=te-1;1==te&&(Ee=te+.01-1);const a=.0555*(Be-f)*Me*we+Math.log10(1/Ee-e/Ee)/Math.log10(Math.E);qe=t/(1+Math.exp(-a))+e,Ue=", Sigmoid function"}else{var qe=Z*be*q*Math.log(Be/Fe+1)/1800;Ue=", Logarithmic formula"}var We=$;const ke=n($,1);var Le="",ze="";if(G&&q>0){if(Le=", Dynamic ISF/CR: On/",qe>te?(De=", Dynamic ISF limited by autosens_max setting: "+te+" ("+n(qe,2)+"), ",ze=", Autosens/Dynamic Limit: "+te+" ("+n(qe,2)+")",qe=te):qe<ee&&(De=", Dynamic ISF limited by autosens_min setting: "+ee+" ("+n(qe,2)+"). ",ze=", Autosens/Dynamic Limit: "+ee+" ("+n(qe,2)+")",qe=ee),fe){Le+="On";var Ne=". New Dynamic CR: "+n($/=qe,1)+" g/U"}else Ne=" CR: "+We+" g/U",Le+="Off";const e=Z/qe;s.ratio=qe,Pe=". Using Sigmoid function, the autosens ratio has been adjusted with sigmoid factor to: "+n(s.ratio,2)+". New ISF = "+n(e,2)+" mg/dl ("+n(.0555*e,2)+" (mmol/l). CR adjusted from "+n(ke,2)+" to "+n($,2),j+=Ge+Te+Ce+Ue+(De+=_e?Pe:", Dynamic autosens.ratio set to "+n(qe,2)+" with ISF: "+e.toPrecision(3)+" mg/dl/U ("+(.0555*e).toPrecision(3)+" mmol/l/U)")+Le+Ne+Oe}else j+=Ge+"Dynamic Settings disabled";console.log(j),G||fe?G&&i.tddAdjBasal?P+=Le+Ue+ze+Ce+xe:G&&!i.tddAdjBasal&&(P+=Le+Ue+ze+Ce):P+="",.5!==i.smb_delivery_ratio&&(P+=", SMB Ratio: "+Math.min(i.smb_delivery_ratio,1)),""!==B&&"Nothing changed"!==B&&(P+=", Middleware: "+B);var He={},Ze=new Date(U);if(void 0===i||void 0===i.current_basal)return He.error="Error: could not get current basal rate",He;var $e=r(i.current_basal,i)*H,Je=$e;v.useOverride&&(0==v.duration?console.log("Profile Override is active. Override "+n(100*H,0)+"%. Override Duration: Enabled indefinitely"):console.log("Profile Override is active. Override "+n(100*H,0)+"%. Override Expires in: "+v.duration+" min."));var Ke,Qe=new Date(e.date),Ve=n((U-Qe)/60/1e3,1),Xe=e.glucose,Ye=e.noise;Ke=e.delta>-.5?"+"+n(e.delta,0):n(e.delta,0);var et=Math.min(e.delta,e.short_avgdelta),tt=Math.min(e.short_avgdelta,e.long_avgdelta),at=Math.max(e.delta,e.short_avgdelta,e.long_avgdelta);if((Xe<=10||38===Xe||Ye>=3)&&(He.reason="CGM is calibrating, in ??? state, or noise is high"),Xe>60&&0==e.delta&&e.short_avgdelta>-1&&e.short_avgdelta<1&&e.long_avgdelta>-1&&e.long_avgdelta<1&&400!=Xe&&"fakecgm"==e.device&&(console.error("CGM data is unchanged ("+o(Xe,i)+"+"+o(e.delta,i)+") for 5m w/ "+o(e.short_avgdelta,i)+" mg/dL ~15m change & "+o(e.long_avgdelta,2)+" mg/dL ~45m change"),console.error("Simulator mode detected ("+e.device+"): continuing anyway")),Ve>12||Ve<-5?He.reason="If current system time "+U+" is correct, then BG data is too old. The last BG data was read "+Ve+"m ago at "+Qe:0===e.short_avgdelta&&0===e.long_avgdelta&&400!=Xe&&(e.last_cal&&e.last_cal<3?He.reason="CGM was just calibrated":He.reason="CGM data is unchanged ("+o(Xe,i)+"+"+o(e.delta,i)+") for 5m w/ "+o(e.short_avgdelta,i)+" mg/dL ~15m change & "+o(e.long_avgdelta,i)+" mg/dL ~45m change"),400!=Xe&&(Xe<=10||38===Xe||Ye>=3||Ve>12||Ve<-5||0===e.short_avgdelta&&0===e.long_avgdelta))return t.rate>=Je?(He.reason+=". Canceling high temp basal of "+t.rate,He.deliverAt=Ze,He.temp="absolute",He.duration=0,He.rate=0,He):0===t.rate&&t.duration>30?(He.reason+=". Shortening "+t.duration+"m long zero temp to 30m. ",He.deliverAt=Ze,He.temp="absolute",He.duration=30,He.rate=0,He):(He.reason+=". Temp "+t.rate+" <= current basal "+Je+"U/hr; doing nothing. ",He);var rt,nt,ot,it,st=i.max_iob;if(void 0!==f&&(nt=f),void 0!==i.max_bg&&(ot=f),void 0!==i.enableSMB_high_bg_target&&(it=i.enableSMB_high_bg_target),void 0===f)return He.error="Error: could not determine target_bg. ",He;rt=f;var lt=i.exercise_mode||i.high_temptarget_raises_sensitivity||v.isEnabled,ut=100,mt=160;if(mt=i.half_basal_exercise_target,v.isEnabled){const e=v.hbt;console.log("Half Basal Target used: "+o(e,i)+" "+i.out_units),mt=e}else console.log("Default Half Basal Target used: "+o(mt,i)+" "+i.out_units);if(lt&&i.temptargetSet&&rt>ut||i.low_temptarget_lowers_sensitivity&&i.temptargetSet&&rt<ut||v.isEnabled&&i.temptargetSet&&rt<ut){var dt=mt-ut;sensitivityRatio=dt*(dt+rt-ut)<=0?i.autosens_max:dt/(dt+rt-ut),sensitivityRatio=Math.min(sensitivityRatio,i.autosens_max),sensitivityRatio=n(sensitivityRatio,2),process.stderr.write("Sensitivity ratio set to "+sensitivityRatio+" based on temp target of "+rt+"; ")}else void 0!==s&&s&&(sensitivityRatio=s.ratio,0===b||6===b||b===i.min_bg||i.temptargetSet||(rt=b,console.log("Current Override Profile Target: "+o(b,i)+" "+i.out_units)),process.stderr.write("Autosens ratio: "+sensitivityRatio+"; "));if(i.temptargetSet&&rt<ut&&G&&Be>=rt&&sensitivityRatio<qe&&(s.ratio=qe*(ut/rt),s.ratio=Math.min(s.ratio,i.autosens_max),sensitivityRatio=n(s.ratio,2),console.log("Dynamic ratio increased from "+n(qe,2)+" to "+n(s.ratio,2)+" due to a low temp target ("+rt+").")),sensitivityRatio&&!G?(Je=i.current_basal*H*sensitivityRatio,Je=r(Je,i)):G&&i.tddAdjBasal&&(Je=i.current_basal*we*H,Je=r(Je,i),K>0&&(process.stderr.write("TDD-adjustment of basals activated, using tdd24h_14d_Ratio "+n(we,2)+", TDD 24h = "+n(se,2)+"U, Weighted average TDD = "+n(N,2)+"U, (Weight percentage = "+J+"), Total data of TDDs (up to 14 days) average = "+n(K,2)+"U. "),Je!==$e*H?process.stderr.write("Adjusting basal from "+$e*H+" U/h to "+Je+" U/h; "):process.stderr.write("Basal unchanged: "+Je+" U/h; "))),i.temptargetSet);else if(void 0!==s&&s&&(i.sensitivity_raises_target&&s.ratio<1||i.resistance_lowers_target&&s.ratio>1)){nt=n((nt-60)/s.ratio)+60,ot=n((ot-60)/s.ratio)+60;var ct=n((rt-60)/s.ratio)+60;rt===(ct=Math.max(80,ct))?process.stderr.write("target_bg unchanged: "+o(ct,i)+"; "):process.stderr.write("target_bg from "+o(ct,i)+" to "+o(ct,i)+"; "),rt=ct}var gt=o(rt,i);rt!=f&&(gt=0!==b&&6!==b&&b!==rt?o(f,i)+"→"+o(b,i)+"→"+o(rt,i):o(f,i)+"→"+o(rt,i));var ht=200,pt=200,vt=200;if(e.noise>=2){var Bt=Math.max(1.1,i.noisyCGMTargetMultiplier);Math.min(250,i.maxRaw),ht=n(Math.min(200,nt*Bt)),pt=n(Math.min(200,rt*Bt)),vt=n(Math.min(200,ot*Bt)),process.stderr.write("Raising target_bg for noisy / raw CGM data, from "+o(ct,i)+" to "+o(pt,i)+"; "),nt=ht,rt=pt,ot=vt}T=nt-.5*(nt-40),T=Math.min(Math.max(i.threshold_setting,T,60),120),console.error("Threshold set to ${convert_bg(threshold, profile)}");var ft="",bt=(n(Z,1),Z);if(void 0!==s&&s&&((bt=n(bt=Z/sensitivityRatio,1))!==Z?process.stderr.write("ISF from "+o(Z,i)+" to "+o(bt,i)):process.stderr.write("ISF unchanged: "+o(bt,i)),ft+="Autosens ratio: "+n(sensitivityRatio,2)+", ISF: "+o(Z,i)+"→"+o(bt,i)),console.error("CR:"+$),void 0===a)return He.error="Error: iob_data undefined. ",He;var Mt,_t=a;if(a.length,a.length>1&&(a=_t[0]),void 0===a.activity||void 0===a.iob)return He.error="Error: iob_data missing some property. ",He;var yt=((Mt=void 0!==a.lastTemp?n((new Date(U).getTime()-a.lastTemp.date)/6e4):0)+t.duration)%30;if(console.error("currenttemp:"+t.rate+" lastTempAge:"+Mt+"m, tempModulus:"+yt+"m"),He.temp="absolute",He.deliverAt=Ze,m&&t&&a.lastTemp&&t.rate!==a.lastTemp.rate&&Mt>10&&t.duration)return He.reason="Warning: currenttemp rate "+t.rate+" != lastTemp rate "+a.lastTemp.rate+" from pumphistory; canceling temp",u.setTempBasal(0,0,i,He,t);if(t&&a.lastTemp&&t.duration>0){var xt=Mt-a.lastTemp.duration;if(xt>5&&Mt>10)return He.reason="Warning: currenttemp running but lastTemp from pumphistory ended "+xt+"m ago; canceling temp",u.setTempBasal(0,0,i,He,t)}var St=n(-a.activity*bt*5,2),Dt=n(6*(et-St));Dt<0&&(Dt=n(6*(tt-St)))<0&&(Dt=n(6*(e.long_avgdelta-St)));var wt,Gt=(wt=a.iob>0?n(Xe-a.iob*bt):n(Xe-a.iob*Math.min(bt,Z)))+Dt;if(void 0===Gt||isNaN(Gt))return He.error="Error: could not calculate eventualBG. Sensitivity: "+bt+" Deviation: "+Dt,He;var Ct,Tt,Ut=function(e,t,a){return n(a+(e-t)/24,1)}(rt,Gt,St);He={temp:"absolute",bg:Xe,tick:Ke,eventualBG:Gt,insulinReq:0,reservoir:d,deliverAt:Ze,sensitivityRatio,CR:n($,1),TDD:se,insulin:ve,current_target:rt,insulinForManualBolus:C,manualBolusErrorString:0,minDelta:et,expectedDelta:Ut,minGuardBG:Tt,minPredBG:Ct,threshold:o(T,i)};var Ot=[],Rt=[],At=[],It=[];Ot.push(Xe),Rt.push(Xe),It.push(Xe),At.push(Xe);let Ft=!1;S?(console.error("SMBs are always off."),Ft=!1):Ft=function(e,t,a,r,n,i,s,l){if(s.smbIsOff){let e=new Date(l.getHours()),t=s.start,a=s.end;if(t<a&&e>=t&&e<a)return console.error("SMB disabled: current time is in SMB disabled scheduled"),!1;if(t>a&&(e>=t||e<a))return console.error("SMB disabled: current time is in SMB disabled scheduled"),!1;if(0==t&&0==a)return console.error("SMB disabled: current time is in SMB disabled scheduled"),!1;if(t==a&&e==t)return console.error("SMB disabled: current time is in SMB disabled scheduled"),!1}return t?!e.allowSMB_with_high_temptarget&&e.temptargetSet&&n>100?(console.error("SMB disabled due to high temptarget of "+n),!1):!0===a.bwFound&&!1===e.A52_risk_enable?(console.error("SMB disabled due to Bolus Wizard activity in the last 6 hours."),!1):400==r?(console.error("Invalid CGM (HIGH). SMBs disabled."),!1):!0===e.enableSMB_always?(a.bwFound?console.error("Warning: SMB enabled within 6h of using Bolus Wizard: be sure to easy bolus 30s before using Bolus Wizard"):console.error("SMB enabled due to enableSMB_always"),!0):!0===e.enableSMB_with_COB&&a.mealCOB?(a.bwCarbs?console.error("Warning: SMB enabled with Bolus Wizard carbs: be sure to easy bolus 30s before using Bolus Wizard"):console.error("SMB enabled for COB of "+a.mealCOB),!0):!0===e.enableSMB_after_carbs&&a.carbs?(a.bwCarbs?console.error("Warning: SMB enabled with Bolus Wizard carbs: be sure to easy bolus 30s before using Bolus Wizard"):console.error("SMB enabled for 6h after carb entry"),!0):!0===e.enableSMB_with_temptarget&&e.temptargetSet&&n<100?(a.bwFound?console.error("Warning: SMB enabled within 6h of using Bolus Wizard: be sure to easy bolus 30s before using Bolus Wizard"):console.error("SMB enabled for temptarget of "+o(n,e)),!0):!0===e.enableSMB_high_bg&&null!==i&&r>=i?(console.error("Checking BG to see if High for SMB enablement."),console.error("Current BG",r," | High BG ",i),a.bwFound?console.error("Warning: High BG SMB enabled within 6h of using Bolus Wizard: be sure to easy bolus 30s before using Bolus Wizard"):console.error("High BG detected. Enabling SMB."),!0):(console.error("SMB disabled (no enableSMB preferences active or no condition satisfied)"),!1):(console.error("SMB disabled (!microBolusAllowed)"),!1)}(i,m,l,Xe,rt,it,v,U);var jt,Pt=i.enableUAM,Et=0;Et=n(et-St,1);var qt=n(et-St,1);csf=bt/$,console.error("profile.sens:"+o(Z,i)+", sens:"+o(bt,i)+", CSF:"+n(csf,1));var Wt=n(30*csf*5/60,1);Et>Wt&&(console.error("Limiting carb impact from "+Et+" to "+Wt+"mg/dL/5m (30g/h)"),Et=Wt);var kt=3;sensitivityRatio&&(kt/=sensitivityRatio);var Lt=kt;if(l.carbs){kt=Math.max(kt,l.mealCOB/20);var zt=n((new Date(U).getTime()-l.lastCarbTime)/6e4),Nt=(l.carbs-l.mealCOB)/l.carbs;Lt=n(Lt=kt+1.5*zt/60,1),console.error("Last carbs "+zt+" minutes ago; remainingCATime:"+Lt+"hours; "+n(100*Nt,1)+"% carbs absorbed")}var Ht=Math.max(0,Et/5*60*Lt/2)/csf,Zt=90,$t=1;i.remainingCarbsCap&&(Zt=Math.min(90,i.remainingCarbsCap)),i.remainingCarbsFraction&&($t=Math.min(1,i.remainingCarbsFraction));var Jt=1-$t,Kt=Math.max(0,l.mealCOB-Ht-l.carbs*Jt),Qt=(Kt=Math.min(Zt,Kt))*csf*5/60/(Lt/2),Vt=n(l.slopeFromMaxDeviation,2),Xt=n(l.slopeFromMinDeviation,2),Yt=Math.min(Vt,-Xt/3);jt=0===Et?0:Math.min(60*Lt/5/2,Math.max(0,l.mealCOB*csf/Et)),console.error("Carb Impact:"+Et+"mg/dL per 5m; CI Duration:"+n(5*jt/60*2,1)+"hours; remaining CI ("+Lt/2+"h peak):"+n(Qt,1)+"mg/dL per 5m");var ea,ta,aa,ra,na=999,oa=999,ia=999,sa=999,la=999,ua=999,ma=999,da=Gt,ca=Xe,ga=Xe,ha=0,pa=[],va=[];try{_t.forEach((function(e){var t=n(-e.activity*bt*5,2),a=n(-e.iobWithZeroTemp.activity*bt*5,2),r=wt,o=Et*(1-Math.min(1,Rt.length/12));!0===(G&&!_e)?(da=Rt[Rt.length-1]+n(-e.activity*(1800/(q*be*Math.log(Math.max(Rt[Rt.length-1],39)/Fe+1)))*5,2)+o,r=It[It.length-1]+n(-e.iobWithZeroTemp.activity*(1800/(q*be*Math.log(Math.max(It[It.length-1],39)/Fe+1)))*5,2),console.log("Dynamic ISF (Logarithmic Formula) )adjusted predictions for IOB and ZT: IOBpredBG: "+n(da,2)+" , ZTpredBG: "+n(r,2))):(da=Rt[Rt.length-1]+t+o,r=It[It.length-1]+a);var i=Math.max(0,Math.max(0,Et)*(1-Ot.length/Math.max(2*jt,1))),s=Math.min(Ot.length,12*Lt-Ot.length),l=Math.max(0,s/(Lt/2*12)*Qt);pa.push(n(l,0)),va.push(n(i,0)),COBpredBG=Ot[Ot.length-1]+t+Math.min(0,o)+i+l;var u=Math.max(0,qt+At.length*Yt),m=Math.max(0,qt*(1-At.length/Math.max(36,1))),d=Math.min(u,m);d>0&&(ha=n(5*(At.length+1)/60,1)),!0===(G&&!_e)?(UAMpredBG=At[At.length-1]+n(-e.activity*(1800/(q*be*Math.log(Math.max(At[At.length-1],39)/Fe+1)))*5,2)+Math.min(0,o)+d,console.log("Dynamic ISF (Logarithmic Formula) adjusted prediction for UAM: UAMpredBG: "+n(UAMpredBG,2))):UAMpredBG=At[At.length-1]+t+Math.min(0,o)+d,Rt.length<48&&Rt.push(da),Ot.length<48&&Ot.push(COBpredBG),At.length<48&&At.push(UAMpredBG),It.length<48&&It.push(r),COBpredBG<sa&&(sa=n(COBpredBG)),UAMpredBG<la&&(la=n(UAMpredBG)),da<ua&&(ua=n(da)),r<ma&&(ma=n(r)),Rt.length>18&&da<na&&(na=n(da)),da>ca&&(ca=da),(jt||Qt>0)&&Ot.length>18&&COBpredBG<oa&&(oa=n(COBpredBG)),(jt||Qt>0)&&COBpredBG>ca&&(ga=COBpredBG),Pt&&At.length>12&&UAMpredBG<ia&&(ia=n(UAMpredBG)),Pt&&UAMpredBG>ca&&UAMpredBG}))}catch(e){console.error("Problem with iobArray.  Optional feature Advanced Meal Assist disabled")}l.mealCOB&&(console.error("predCIs (mg/dL/5m):"+va.join(" ")),console.error("remainingCIs:      "+pa.join(" "))),He.predBGs={},Rt.forEach((function(e,t,a){a[t]=n(Math.min(401,Math.max(39,e)))}));for(var Ba=Rt.length-1;Ba>12&&Rt[Ba-1]===Rt[Ba];Ba--)Rt.pop();for(He.predBGs.IOB=Rt,ta=n(Rt[Rt.length-1]),It.forEach((function(e,t,a){a[t]=n(Math.min(401,Math.max(39,e)))})),Ba=It.length-1;Ba>6&&!(It[Ba-1]>=It[Ba]||It[Ba]<=rt);Ba--)It.pop();if(He.predBGs.ZT=It,n(It[It.length-1]),l.mealCOB>0&&(Et>0||Qt>0)){for(Ot.forEach((function(e,t,a){a[t]=n(Math.min(1500,Math.max(39,e)))})),Ba=Ot.length-1;Ba>12&&Ot[Ba-1]===Ot[Ba];Ba--)Ot.pop();He.predBGs.COB=Ot,aa=n(Ot[Ot.length-1]),Gt=Math.max(Gt,n(Ot[Ot.length-1])),console.error("COBpredBG: "+n(Ot[Ot.length-1]))}if(Et>0||Qt>0){if(Pt){for(At.forEach((function(e,t,a){a[t]=n(Math.min(401,Math.max(39,e)))})),Ba=At.length-1;Ba>12&&At[Ba-1]===At[Ba];Ba--)At.pop();He.predBGs.UAM=At,ra=n(At[At.length-1]),At[At.length-1]&&(Gt=Math.max(Gt,n(At[At.length-1])))}He.eventualBG=Gt}console.error("UAM Impact:"+qt+"mg/dL per 5m; UAM Duration:"+ha+"hours"),na=Math.max(39,na),oa=Math.max(39,oa),ia=Math.max(39,ia),Ct=n(na);var fa=l.mealCOB/l.carbs;ea=n(ia<999&&oa<999?(1-fa)*UAMpredBG+fa*COBpredBG:oa<999?(da+COBpredBG)/2:ia<999?(da+UAMpredBG)/2:da),ma>ea&&(ea=ma),Tt=n(Tt=jt||Qt>0?Pt?fa*sa+(1-fa)*la:sa:Pt?la:ua);var ba=ia;if(ma<T)ba=(ia+ma)/2;else if(ma<rt){var Ma=(ma-T)/(rt-T);ba=(ia+(ia*Ma+ma*(1-Ma)))/2}else ma>ia&&(ba=(ia+ma)/2);if(ba=n(ba),l.carbs)if(!Pt&&oa<999)Ct=n(Math.max(na,oa));else if(oa<999){var _a=fa*oa+(1-fa)*ba;Ct=n(Math.max(na,oa,_a))}else Ct=Pt?ba:Tt;else Pt&&(Ct=n(Math.max(na,ba)));Ct=Math.min(Ct,ea),process.stderr.write("minPredBG: "+Ct+" minIOBPredBG: "+na+" minZTGuardBG: "+ma),oa<999&&process.stderr.write(" minCOBPredBG: "+oa),ia<999&&process.stderr.write(" minUAMPredBG: "+ia),console.error(" avgPredBG:"+ea+" COB/Carbs:"+l.mealCOB+"/"+l.carbs),ga>Xe&&(Ct=Math.min(Ct,ga)),He.COB=l.mealCOB,He.IOB=a.iob,He.BGI=o(St,i),He.deviation=o(Dt,i),He.ISF=o(bt,i),He.CR=n($,1),He.target_bg=o(rt,i),He.TDD=n(se,2),He.current_target=n(rt,0);var ya=He.CR;ke!=He.CR&&(ya=ke+"→"+He.CR),He.reason=ft+", COB: "+He.COB+", Dev: "+He.deviation+", BGI: "+He.BGI+", CR: "+ya+", Target: "+gt+", minPredBG "+o(Ct,i)+", minGuardBG "+o(Tt,i)+", IOBpredBG "+o(ta,i),aa>0&&(He.reason+=", COBpredBG "+o(aa,i)),ra>0&&(He.reason+=", UAMpredBG "+o(ra,i)),He.reason+=P,He.reason+="; ";var xa=wt;xa<40&&(xa=Math.min(Tt,xa));var Sa,Da=T-xa,wa=240,Ga=240;if(l.mealCOB>0&&(Et>0||Qt>0)){for(Ba=0;Ba<Ot.length;Ba++)if(Ot[Ba]<nt){wa=5*Ba;break}for(Ba=0;Ba<Ot.length;Ba++)if(Ot[Ba]<T){Ga=5*Ba;break}}else{for(Ba=0;Ba<Rt.length;Ba++)if(Rt[Ba]<nt){wa=5*Ba;break}for(Ba=0;Ba<Rt.length;Ba++)if(Rt[Ba]<T){Ga=5*Ba;break}}Ft&&Tt<T&&(console.error("minGuardBG "+o(Tt,i)+" projected below "+o(T,i)+" - disabling SMB"),He.manualBolusErrorString=1,He.minGuardBG=Tt,He.insulinForManualBolus=n((He.eventualBG-He.target_bg)/bt,2),Ft=!1),void 0===i.maxDelta_bg_threshold&&(Sa=.2),void 0!==i.maxDelta_bg_threshold&&(Sa=Math.min(i.maxDelta_bg_threshold,.4)),at>Sa*Xe&&(console.error("maxDelta "+o(at,i)+" > "+100*Sa+"% of BG "+o(Xe,i)+" - disabling SMB"),He.reason+="maxDelta "+o(at,i)+" > "+100*Sa+"% of BG "+o(Xe,i)+" - SMB disabled!, ",Ft=!1),console.error("BG projected to remain above "+o(nt,i)+" for "+wa+"minutes"),(Ga<240||wa<60)&&console.error("BG projected to remain above "+o(T,i)+" for "+Ga+"minutes");var Ca=Ga,Ta=i.current_basal*H*bt*Ca/60,Ua=Math.max(0,l.mealCOB-.25*l.carbs),Oa=(Da-Ta)/csf-Ua;Ta=n(Ta),Oa=n(Oa),console.error("naive_eventualBG:",wt,"bgUndershoot:",Da,"zeroTempDuration:",Ca,"zeroTempEffect:",Ta,"carbsReq:",Oa),"Could not parse clock data"==l.reason?console.error("carbsReq unknown: Could not parse clock data"):Oa>=i.carbsReqThreshold&&Ga<=45&&(He.carbsReq=Oa,He.reason+=Oa+" add'l carbs req w/in "+Ga+"m; ");var Ra=0;if(Xe<T&&a.iob<-i.current_basal*H*20/60&&et>0&&et>Ut)He.reason+="IOB "+a.iob+" < "+n(-i.current_basal*H*20/60,2),He.reason+=" and minDelta "+o(et,i)+" > expectedDelta "+o(Ut,i)+"; ";else if(Xe<T||Tt<T)return He.reason+="minGuardBG "+o(Tt,i)+"<"+o(T,i),Da=rt-Tt,Tt<T&&(He.manualBolusErrorString=2,He.minGuardBG=Tt),He.insulinForManualBolus=n((Gt-rt)/bt,2),Ra=n(Da/bt*60/i.current_basal*H),Ra=30*n(Ra/30),Ra=Math.min(120,Math.max(30,Ra)),u.setTempBasal(0,Ra,i,He,t);if(i.skip_neutral_temps&&He.deliverAt.getMinutes()>=55)return He.reason+="; Canceling temp at "+He.deliverAt.getMinutes()+"m past the hour. ",u.setTempBasal(0,0,i,He,t);var Aa=0,Ia=Je,Fa=0;if(Gt<nt){if(He.reason+="Eventual BG "+o(Gt,i)+" < "+o(nt,i),et>Ut&&et>0&&!Oa)return wt<40?(He.reason+=", naive_eventualBG < 40. ",u.setTempBasal(0,30,i,He,t)):(e.delta>et?He.reason+=", but Delta "+o(Ke,i)+" > expectedDelta "+o(Ut,i):He.reason+=", but Min. Delta "+et.toFixed(2)+" > Exp. Delta "+o(Ut,i),t.duration>15&&r(Je,i)===r(t.rate,i)?(He.reason+=", temp "+t.rate+" ~ req "+Je+"U/hr. ",He):(He.reason+="; setting current basal of "+Je+" as temp. ",u.setTempBasal(Je,30,i,He,t)));Aa=n(Aa=2*Math.min(0,(Gt-rt)/bt),2);var ja=Math.min(0,(wt-rt)/bt);ja=n(ja,2),et<0&&et>Ut&&(Aa=n(Aa*(et/Ut),2)),Ia=r(Ia=Je+2*Aa,i),Fa=t.duration*(t.rate-Je)/60;var Pa=Math.min(Aa,ja);if(console.log("naiveInsulinReq:"+ja),Fa<Pa-.3*Je)return He.reason+=", "+t.duration+"m@"+t.rate.toFixed(2)+" is a lot less than needed. ",u.setTempBasal(Ia,30,i,He,t);if(void 0!==t.rate&&t.duration>5&&Ia>=.8*t.rate)return He.reason+=", temp "+t.rate+" ~< req "+Ia+"U/hr. ",He;if(Ia<=0){if((Ra=n((Da=rt-wt)/bt*60/i.current_basal*H))<0?Ra=0:(Ra=30*n(Ra/30),Ra=Math.min(120,Math.max(0,Ra))),Ra>0)return He.reason+=", setting "+Ra+"m zero temp. ",u.setTempBasal(Ia,Ra,i,He,t)}else He.reason+=", setting "+Ia+"U/hr. ";return u.setTempBasal(Ia,30,i,He,t)}if(et<Ut&&(He.minDelta=et,He.expectedDelta=Ut,(Ut-et>=2||Ut+-1*et>=2)&&(He.manualBolusErrorString=et>=0&&Ut>0?3:et<0&&Ut<=0||et<0&&Ut>=0?4:5),He.insulinForManualBolus=n((He.eventualBG-He.target_bg)/bt,2),!m||!Ft))return e.delta<et?He.reason+="Eventual BG "+o(Gt,i)+" > "+o(nt,i)+" but Delta "+o(Ke,i)+" < Exp. Delta "+o(Ut,i):He.reason+="Eventual BG "+o(Gt,i)+" > "+o(nt,i)+" but Min. Delta "+et.toFixed(2)+" < Exp. Delta "+o(Ut,i),t.duration>15&&r(Je,i)===r(t.rate,i)?(He.reason+=", temp "+t.rate+" ~ req "+Je+"U/hr. ",He):(He.reason+="; setting current basal of "+Je+" as temp. ",u.setTempBasal(Je,30,i,He,t));if(Math.min(Gt,Ct)<ot&&(Ct<nt&&Gt>nt&&(He.manualBolusErrorString=6,He.insulinForManualBolus=n((He.eventualBG-He.target_bg)/bt,2),He.minPredBG=Ct),!m||!Ft))return He.reason+=o(Gt,i)+"-"+o(Ct,i)+" in range: no temp required",t.duration>15&&r(Je,i)===r(t.rate,i)?(He.reason+=", temp "+t.rate+" ~ req "+Je+"U/hr. ",He):(He.reason+="; setting current basal of "+Je+" as temp. ",u.setTempBasal(Je,30,i,He,t));if(Gt>=ot&&(He.reason+="Eventual BG "+o(Gt,i)+" >= "+o(ot,i)+", ",Gt>ot&&(He.insulinForManualBolus=n((Gt-rt)/bt,2))),a.iob>st)return He.reason+="IOB "+n(a.iob,2)+" > max_iob "+st,t.duration>15&&r(Je,i)===r(t.rate,i)?(He.reason+=", temp "+t.rate+" ~ req "+Je+"U/hr. ",He):(He.reason+="; setting current basal of "+Je+" as temp. ",u.setTempBasal(Je,30,i,He,t));Aa=n((Math.min(Ct,Gt)-rt)/bt,2),C=n((Gt-rt)/bt,2),Aa>st-a.iob?(console.error("SMB limited by maxIOB: "+st-a.iob+" (. insulinReq: "+Aa+" U)"),He.reason+="max_iob "+st+", ",Aa=st-a.iob):console.error("SMB not limited by maxIOB ( insulinReq: "+Aa+" U)."),C>st-a.iob?(console.error("Ev. Bolus limited by maxIOB: "+st-a.iob+" (. insulinForManualBolus: "+C+" U)"),He.reason+="max_iob "+st+", "):console.error("Ev. Bolus would not be limited by maxIOB ( insulinForManualBolus: "+C+" U)."),Ia=r(Ia=Je+2*Aa,i),Aa=n(Aa,3),He.insulinReq=Aa;var Ea=n((new Date(U).getTime()-a.lastBolusTime)/6e4,1);if(m&&Ft&&Xe>T){var qa=30;void 0!==i.maxSMBBasalMinutes&&(qa=i.maxSMBBasalMinutes);var Wa=30;void 0!==i.maxUAMSMBBasalMinutes&&(Wa=i.maxUAMSMBBasalMinutes),v.useOverride&&M&&D!==qa&&(console.error("SMB Max Minutes - setting overriden from "+qa+" to "+D),qa=D),v.useOverride&&M&&w!==Wa&&(console.error("UAM Max Minutes - setting overriden from "+Wa+" to "+w),Wa=w);var ka=n(l.mealCOB/$,3),La=0;void 0===qa?(La=n(i.current_basal*H*30/60,1),console.error("smbMinutesSetting undefined: defaulting to 30m"),Aa>La&&console.error("SMB limited by maxBolus: "+La+" ( "+Aa+" U)")):a.iob>ka&&a.iob>0?(console.error("IOB"+a.iob+"> COB"+l.mealCOB+"; mealInsulinReq ="+ka),Wa?(console.error("maxUAMSMBBasalMinutes: "+Wa+", profile.current_basal: "+i.current_basal*H),La=n(i.current_basal*H*Wa/60,1)):(console.error("maxUAMSMBBasalMinutes undefined: defaulting to 30m"),La=n(i.current_basal*H*30/60,1)),Aa>La?console.error("SMB limited by maxUAMSMBBasalMinutes [ "+Wa+"m ]: "+La+"U ( "+Aa+"U )"):console.error("SMB is not limited by maxUAMSMBBasalMinutes. ( insulinReq: "+Aa+"U )")):(console.error(".maxSMBBasalMinutes: "+qa+", profile.current_basal: "+i.current_basal*H),Aa>(La=n(i.current_basal*H*qa/60,1))?console.error("SMB limited by maxSMBBasalMinutes: "+qa+"m ]: "+La+"U ( insulinReq: "+Aa+"U )"):console.error("SMB is not limited by maxSMBBasalMinutes. ( insulinReq: "+Aa+"U )"));var za=i.bolus_increment,Na=1/za,Ha=Math.min(i.smb_delivery_ratio,1);.5!=Ha&&console.error("SMB Delivery Ratio changed from default 0.5 to "+n(Ha,2));var Za=Math.min(Aa*Ha,La);Za=Math.floor(Za*Na)/Na,Ra=n((rt-(wt+na)/2)/bt*60/i.current_basal*H),Aa>0&&Za<za&&(Ra=0);var $a=0;Ra<=0?Ra=0:Ra>=30?(Ra=30*n(Ra/30),Ra=Math.min(60,Math.max(0,Ra))):($a=n(Je*Ra/30,2),Ra=30),He.reason+=" insulinReq "+Aa,Za>=La&&(He.reason+="; maxBolus "+La),Ra>0&&(He.reason+="; setting "+Ra+"m low temp of "+$a+"U/h"),He.reason+=". ";var Ja=3;i.SMBInterval&&(Ja=Math.min(10,Math.max(1,i.SMBInterval)));var Ka=n(Ja-Ea,0),Qa=n(60*(Ja-Ea),0)%60;if(console.error("naive_eventualBG "+wt+","+Ra+"m "+$a+"U/h temp needed; last bolus "+Ea+"m ago; maxBolus: "+La),Ea>Ja?Za>0&&(He.units=Za,He.reason+="Microbolusing "+Za+"U. "):He.reason+="Waiting "+Ka+"m "+Qa+"s to microbolus again. ",Ra>0)return He.rate=$a,He.duration=Ra,He}var Va=u.getMaxSafeBasal(i);return 400==Xe?u.setTempBasal(i.current_basal,30,i,He,t):(Ia>Va&&(He.reason+="adj. req. rate: "+Ia+" to maxSafeBasal: "+n(Va,2)+", ",Ia=r(Va,i)),(Fa=t.duration*(t.rate-Je)/60)>=2*Aa?(He.reason+=t.duration+"m@"+t.rate.toFixed(2)+" > 2 * insulinReq. Setting temp basal of "+Ia+"U/hr. ",u.setTempBasal(Ia,30,i,He,t)):void 0===t.duration||0===t.duration?(He.reason+="no temp, setting "+Ia+"U/hr. ",u.setTempBasal(Ia,30,i,He,t)):t.duration>5&&r(Ia,i)<=r(t.rate,i)?(He.reason+="temp "+t.rate+" >~ req "+Ia+"U/hr. ",He):(He.reason+="temp "+t.rate+"<"+Ia+"U/hr. ",u.setTempBasal(Ia,30,i,He,t)))}},3531:(e,t,a)=>{var r=a(2296);e.exports=function(e,t){var a=20;return void 0!==t&&"string"==typeof t.model&&(r(t.model,"54")||r(t.model,"23"))&&(a=40),e<1?Math.round(e*a)/a:e<10?Math.round(20*e)/20:Math.round(10*e)/10}},1873:(e,t,a)=>{var r=a(9325).Symbol;e.exports=r},4932:e=>{e.exports=function(e,t){for(var a=-1,r=null==e?0:e.length,n=Array(r);++a<r;)n[a]=t(e[a],a,e);return n}},7133:e=>{e.exports=function(e,t,a){return e==e&&(void 0!==a&&(e=e<=a?e:a),void 0!==t&&(e=e>=t?e:t)),e}},2552:(e,t,a)=>{var r=a(1873),n=a(659),o=a(9350),i=r?r.toStringTag:void 0;e.exports=function(e){return null==e?void 0===e?"[object Undefined]":"[object Null]":i&&i in Object(e)?n(e):o(e)}},7556:(e,t,a)=>{var r=a(1873),n=a(4932),o=a(6449),i=a(4394),s=r?r.prototype:void 0,l=s?s.toString:void 0;e.exports=function e(t){if("string"==typeof t)return t;if(o(t))return n(t,e)+"";if(i(t))return l?l.call(t):"";var a=t+"";return"0"==a&&1/t==-1/0?"-0":a}},4128:(e,t,a)=>{var r=a(1800),n=/^\s+/;e.exports=function(e){return e?e.slice(0,r(e)+1).replace(n,""):e}},4840:(e,t,a)=>{var r="object"==typeof a.g&&a.g&&a.g.Object===Object&&a.g;e.exports=r},659:(e,t,a)=>{var r=a(1873),n=Object.prototype,o=n.hasOwnProperty,i=n.toString,s=r?r.toStringTag:void 0;e.exports=function(e){var t=o.call(e,s),a=e[s];try{e[s]=void 0;var r=!0}catch(e){}var n=i.call(e);return r&&(t?e[s]=a:delete e[s]),n}},9350:e=>{var t=Object.prototype.toString;e.exports=function(e){return t.call(e)}},9325:(e,t,a)=>{var r=a(4840),n="object"==typeof self&&self&&self.Object===Object&&self,o=r||n||Function("return this")();e.exports=o},1800:e=>{var t=/\s/;e.exports=function(e){for(var a=e.length;a--&&t.test(e.charAt(a)););return a}},2296:(e,t,a)=>{var r=a(7133),n=a(7556),o=a(1489),i=a(3222);e.exports=function(e,t,a){e=i(e),t=n(t);var s=e.length,l=a=void 0===a?s:r(o(a),0,s);return(a-=t.length)>=0&&e.slice(a,l)==t}},6449:e=>{var t=Array.isArray;e.exports=t},3805:e=>{e.exports=function(e){var t=typeof e;return null!=e&&("object"==t||"function"==t)}},346:e=>{e.exports=function(e){return null!=e&&"object"==typeof e}},4394:(e,t,a)=>{var r=a(2552),n=a(346);e.exports=function(e){return"symbol"==typeof e||n(e)&&"[object Symbol]"==r(e)}},7400:(e,t,a)=>{var r=a(6993),n=1/0;e.exports=function(e){return e?(e=r(e))===n||e===-1/0?17976931348623157e292*(e<0?-1:1):e==e?e:0:0===e?e:0}},1489:(e,t,a)=>{var r=a(7400);e.exports=function(e){var t=r(e),a=t%1;return t==t?a?t-a:t:0}},6993:(e,t,a)=>{var r=a(4128),n=a(3805),o=a(4394),i=/^[-+]0x[0-9a-f]+$/i,s=/^0b[01]+$/i,l=/^0o[0-7]+$/i,u=parseInt;e.exports=function(e){if("number"==typeof e)return e;if(o(e))return NaN;if(n(e)){var t="function"==typeof e.valueOf?e.valueOf():e;e=n(t)?t+"":t}if("string"!=typeof e)return 0===e?e:+e;e=r(e);var a=s.test(e);return a||l.test(e)?u(e.slice(2),a?2:8):i.test(e)?NaN:+e}},3222:(e,t,a)=>{var r=a(7556);e.exports=function(e){return null==e?"":r(e)}}},t={};function a(r){var n=t[r];if(void 0!==n)return n.exports;var o=t[r]={exports:{}};return e[r](o,o.exports,a),o.exports}a.g=function(){if("object"==typeof globalThis)return globalThis;try{return this||new Function("return this")()}catch(e){if("object"==typeof window)return window}}();var r=a(2982);freeaps_determineBasal=r})();