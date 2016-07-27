function mod_eddy_tracks(r,cut_off,Dt,dps,update)
%mod_eddy_tracks(r,cut_off,Dt,dps {,update})
%
%  Computes eddy tracking from the eddies features, and saves them
%  as {eddy_tracks(n)} in [path_out,'eddy_tracks',runname].
%
%  - r (in km) use to define the area used to search for eddy centers at
%       successive time steps. Typically the overall speed of the
%       structure per day.
%  - cut_off (days) are the minimum duration tracks recorded
%       use cut_off=0 to use the explicit turnover time (tau) for each eddy
%       use cut_off=1 to keep all eddies
%  - Dt (days) is the tolerance of time steps after eddy disapears
%  - dps is the number of days between 2 time step (dps=1/8 gives 3h)
%  - update is a flag allowing to update an existing detection matrice:
%       update = number of time steps backward to consider
%       update = 0 (default) to compute all the {shapes} time serie
%
%  For a description of the input parameters see param_eddy_tracking.m

%
%  Eddy tracks are connected by comparing the detected eddy fields at
%  sucessive time steps. An eddy in the time 't+dt' is assumed to be the
%  new position of an eddy of the same type detected at 't', if the two 
%  centers are found within an area of 'r*(1+dt/2) + rmax*1.5' km
%  centered around the center position at time 't'. Where rmax is, for each
%  eddy, his mean radius averaged for the last 5 time steps tracked.
%
%  If no eddies are found at 't+Dt' the eddy is considered dissipated and
%  the track closed.
%
%  In case two or more eddies are found within the same area, the track is
%  connect the centers by minimizing the cost funtion of an assignment matrice
%  considering all the new centers at t. The cost function is a NxM matrix:
%       C = sqrt ( d/D ² + dRo/Ro ² + dBu/Bu ² + dvort/vortM ² )
%   with N in row is the number of eddies in t+dt
%        M in colum is the number of new eddies at t
%
%  
%  Tracked eddy are saved/updated as the structure array {traks(n)}
%  in [path_out,'eddy_tracks',runname'] with fields following {centers}
%  and {shapes}, where 'n' is the total number of track recorded and
%  'm' is the step index of a given track:
%  - step(m): steps when the eddy centers forming the track where
%                       detected;
%  - type(m): type of eddy;
%  - x1(m) and y1(m): x and y of the eddy centers forming the track;
%  - shapes1{m} : shapes of the eddies forming the track; (each 
%           cell is a 2xL array containing the x (first row) and 
%           y (second row) coordinates of the 'L' vertices defining
%           the eddy shape for the 'm'-th step.
%   ...
%{
    x2
    y2
    dc
    ds
    velmax1
    tau1
    deta1
    nrho1
    rmax1
    aire1
    alpha
    rsquare
    rmse
    velmax3
    tau3
    deta3
    rmax3
    aire3
    xbary1
    ybary1
    ellip1
    ke1
    vort1
    vortM1
    OW1
    LNAM1
    shapes2
    velmax2
    tau2
    deta2
    nrho2
    rmax2
    aire2
    xbary2
    ybary2
    ellip2
    ke2
    vort2
    vortM2
    OW2
    LNAM2
    calcul
    large1
    large2
    toobig
%}  
%
% Also:
%
%  [path_out,'removed_tracks',runname] contains the number of tracks removed
%  because shorter than 'cut_off' days.
%
%  The function returns a log file [path_out,'log_eddy_tracks',runname,'.txt']
%  which contains warnings relative to the presence of multiple eddies
%  and the evolution of the search matrix within the searching area used
%  to determine the tracks.
%
%  (NOTE: if the file already exist, the new log file will be append to it)
%
%  The same information is saved in [path_out,'warnings_tracks',runname], 
%  an Rx3 array (R is the total number of warnings), where each column
%  represent in the order:
%  - step the warning occurred;
%  - n indice of eddy concerned;
%  - number of eddies detected within the area;
%
%-------------------------
%   Ver. 3.2 Feb.2016 Briac Le Vu
%   Ver. 3.1 2014 LMD
%-------------------------
%
%=========================

global path_out
global runname
global grid_ll
global extended_diags

% No update by default
if nargin==4
    update = 0;
end

% begin the log file
diary([path_out,'log_eddy_tracks',runname,'.txt']);

%----------------------------------------------------------
% load eddy centers and eddy shapes
load([path_out,'eddy_centers',runname]);
load([path_out,'eddy_shapes',runname]);
load([path_out,'warnings_shapes',runname]);

stepF = length(centers);

%----------------------------------------------------------
% Names list from centers and shapes structure
var_name1 = fieldnames(centers2);
var_name2 = fieldnames(shapes1);
var_name3 = fieldnames(shapes2);
var_name4 = {'calcul_curve','large_curve1','large_curve2','too_large2'};

%----------------------------------------------------------
% intitialize/update tracks and search structure arrays
% - search contains all the open tracks;
% - tracks contains all the closed tracks which will be saved;

if update && exist([path_out,'eddy_tracks',runname,'.mat'],'file')
    
% Build record tracks and active search
    
    load([path_out,'removed_tracks',runname])
    load([path_out,'eddy_tracks',runname])
    load([path_out,'warnings_tracks',runname])
    
    step0 = stepF - update + 1;
    
    search_name = fieldnames(tracks);
    
% Remove eddies newer than the updating step

    moved = false(1,length(tracks));

    for i=1:length(tracks)
        % find step earlier than update date
        ind = tracks(i).step < step0;
        
        % record earlier step
        for n=1:length(search_name)
            tracks(i).(search_name{n}) = tracks(i).(search_name{n})(ind);
        end
        
        moved(i) = isempty(tracks(i).step);
    end
    
 	tracks(moved) = [];
    
% Remove warnings newer than the updating step

    ind = warn_tracks(:,1) < step0;
    warn_tracks = warn_tracks(ind,:);

% Remove eddies non active from search and eddies still active from tracks

    search = tracks;
    moved = false(1,length(search));

    for i=1:length(search)

        moved(i) = search(i).step(end) < (step0 - Dt/dps - 1) ;

    end

    search(moved) = [];
    tracks(~moved) = [];
    
else
% preallocate tracks array
    
    switch extended_diags
        case {0, 2}
            tracks = struct('step',{},'type',{},'x1',{},'y1',{},'x2',{},'y2',{},...
                'dc',{},'ds',{},...
                'shapes1',{},'velmax1',{},'tau1',{},'deta1',{},'nrho1',{},'rmax1',{},'aire1',{},...
                'shapes3',{},'velmax3',{},'deta3',{},'rmax3',{},'aire3',{},...
                'shapes2',{},'velmax2',{},'deta2',{},'nrho2',{},'rmax2',{},'aire2',{},...
                'calcul',{},'large1',{},'large2',{},'toobig',{});
        case 1
            tracks = struct('step',{},'type',{},'x1',{},'y1',{},'x2',{},'y2',{},...
                'dc',{},'ds',{},...
                'shapes1',{},'velmax1',{},'tau1',{},'deta1',{},'nrho1',{},'rmax1',{},'aire1',{},...
                'shapes3',{},'velmax3',{},'deta3',{},'rmax3',{},'aire3',{},...
                'alpha',{},'rsquare',{},'rmse',{},...
                'xbary1',{},'ybary1',{},'ellip1',{},'ke1',{},'vort1',{},'vortM1',{},'OW1',{},'LNAM1',{},...
                'shapes2',{},'velmax2',{},'deta2',{},'nrho2',{},'rmax2',{},'aire2',{},...
                'xbary2',{},'ybary2',{},'ellip2',{},...
                'calcul',{},'large1',{},'large2',{},'toobig',{});
        otherwise
            display('Wrong choice of extended_diags option')
            stop
    end

    search = tracks;
    warn_tracks = [];

    step0 = 1;

    search_name = fieldnames(tracks);
    
end

%----------------------------------------------------------
% loop through all the steps in which eddies were detected
for i=step0:stepF
    
    % variables containing data of all the eddies detected for the
    % current step
    
    stp = centers(i).step;
    disp(['Searching step ',num2str(stp),' ... '])
    
    for n=2:length(var_name1)
        eddy.(search_name{n}) = centers2(i).(var_name1{n});
    end
    
    N = length(var_name1);
    for n=1:length(var_name2)
        eddy.(search_name{n+N}) = shapes1(i).(var_name2{n});
    end
    
    N = N + length(var_name2);
    for n=1:length(var_name3)
        eddy.(search_name{n+N}) = shapes2(i).(var_name3{n});
    end
    
    N = N + length(var_name3);
    for n=1:length(var_name4)
        eddy.(search_name{n+N}) = warn_shapes2(i).(var_name4{n});
    end
    
    %----------------------------------------------------------
    % Begin updating eddy tracks ------------------------------
    %----------------------------------------------------------
    if ~isempty(eddy.type)% be sure eddies were present that specific step
        
        %----------------------------------------------------------
        % if first time-step, then all the eddies are open tracks 
        % (added to search open tracks matrix)
        if i==1
            for i2=1:length(eddy.type)
                
                search(i2).step = stp;

                for n=2:length(search_name)
                    search(i2).(search_name{n}) = eddy.(search_name{n})(i2);
                end
               
            end

            % display number of first eddies
            disp([' total eddies: ',num2str(length(search))])
    
        %----------------------------------------------------------
        % if not first step, then open tracks from previous steps
        % are updated with eddies detected for the current step
        else
            
            %----------------------------------------------------------
            % eddy features at current time
            ind_new = nan(length(eddy.type),9);
            
            ind_new(:,1) = eddy.type; % type
            
            switch extended_diags
                case {0, 2}
                    ind_new(:,2) = eddy.x1;
                    ind_new(:,3) = eddy.y1;
                    ind_new(:,4) = eddy.x1;
                    ind_new(:,5) = eddy.y1;
                    ind_new(:,6) = eddy.rmax1; % rmax
                case 1
                    ind_new(:,2) = eddy.x1;
                    ind_new(:,3) = eddy.y1;
                    ind_new(:,4) = eddy.xbary1;
                    ind_new(:,5) = eddy.ybary1;
                    %ind_new(:,6) = max(eddy.a1,eddy.b1); % rmax !bug ellipse!
                    ind_new(:,6) = eddy.rmax1; % rmax
                    ind_new(:,9) = eddy.vortM1 * 1e6; % maximale vorticity
            end
            
            % Ro and Bu numbers
            ind_new(:,7) = eddy.velmax1 .* eddy.rmax1; % Ro = velmax/f./rmax*1e-3
            ind_new(:,8) = eddy.deta1 .* eddy.rmax1; % Bu = g*deta./(f^2*rmax.^2)*1e-3
            
            % Cost matrice Nsearch X Mnew
            C = Inf(length(search),length(ind_new(:,1)));
    
            %----------------------------------------------------------
            % loop all open tracks from the previous time steps
            for i2=1:length(search)
                
                % initialise 
                ind_old = nan(1,9);
                % time steps since every detection
                last = stp - search(i2).step;
                
                j = length(last);
                
                %------------------------------------------------------
                % 1st: find x and y of the eddy centers in open tracks by 
                % scanning among the 'Dt' previous
                % time steps starting with latest step
                
                if last(j)*dps<=Dt

                    %--------------------------------------------------
                    % features of eddy i2 in previous time steps
                    ind_old(1) = search(i2).type(j);

                    switch extended_diags
                        case {0, 2}
                            
                            % LNAM center
                            ind_old(2) = search(i2).x1(j);
                            ind_old(3) = search(i2).y1(j);
                            ind_old(4) = search(i2).x1(j);
                            ind_old(5) = search(i2).y1(j);

                            % rmax from the 5 previous detection
                            ind_old(6) = nanmean(search(i2).rmax1(max(1,j-4):j));
                        
                        case 1
                            
                            % barycenter is more centred and stable
                            ind_old(2) = search(i2).x1(j);
                            ind_old(3) = search(i2).y1(j);
                            ind_old(4) = search(i2).xbary1(j);
                            ind_old(5) = search(i2).ybary1(j);

                            % longer axe of the ellipse from the 5 previous detection
                            %ind_old(6) = mean(max([search(i2).a1(max(1,j-4):j),...
                             %           search(i2).b1(max(1,j-4):j)],[],2));% !bug ellipse!
                            ind_old(6) = nanmean(search(i2).rmax1(max(1,j-4):j));

                            % maximale vorticity
                            ind_old(9) = nanmean(search(i2).vortM1(max(1,j-4):j)) * 1e6;
                    end

                    % Ro number
                    ind_old(7) = nanmean(search(i2).velmax1(max(1,j-4):j) .* ...
                                search(i2).rmax1(max(1,j-4):j));
                            
                    % Bu number
                    ind_old(8) = nanmean(search(i2).deta1(max(1,j-4):j) .* ...
                                search(i2).rmax1(max(1,j-4):j));

                    %--------------------------------------------------
                    % 2nd: find centers after 'last' steps no more than
                    % 'Dt' days that are within 'D' from the search
                    % center then calculate the cost matrix C which is:
                    % C = sqrt ( d/D ² + dRo/Ro ² + dBu/Bu ² + dvort/vortM ² )  
                    % C = sqrt ( d/D ² + dRo/Ro ² + dBu/Bu ² )  

                    % - assumed maximum distance (D):
                    % theorical center moving + mean (last 5 radius, new radius) *1.5
                    %D = r*dps*min(last(j),(1+last(j)/2)) + ind_old(6) * 1.5;%1 2 4
                    %D = r*dps*min(last(j),(1+last(j)/2)) + ind_old(6) * 2;%5 6 3 4
                    D = r*dps*min(last(j),(1+last(j)/2)) + (ind_old(6) + ind_new(:,6))/2 * 1.5;%7

                    % - compute cost matrix for eddy inside D
                    for i3=1:size(ind_new,1)

                    % - Distance between centers (d1) and barycenter (d2)
                        if grid_ll
                            d1 = sw_dist([ind_new(i3,3) ind_old(3)],...
                                        [ind_new(i3,2) ind_old(2)],'km');
                            %d2 = sw_dist([ind_new(i3,5) ind_old(5)],...
                             %           [ind_new(i3,4) ind_old(4)],'km');
                        else
                            d1 = sqrt((ind_new(i3,2) - ind_old(2)).^2 +...
                                    (ind_new(i3,3) - ind_old(3)).^2);
                            %d2 = sqrt((ind_new(i3,4) - ind_old(4)).^2 +...
                             %       (ind_new(i3,5) - ind_old(5)).^2);
                        end

                    % - Cost for eddy of same type at less than 'D' km
                    %   center or barycenter to center or barycenter
                    %    if ind_new(i3,1)==ind_old(1) &&  d2<=D%1 2 5 6
                    %    if ind_new(i3,1)==ind_old(1) && d1<=D%3 4
                        if ind_new(i3,1)==ind_old(1) && d1<=D(i3)%7

                            switch extended_diags
                                case {0, 2}
                                    %C(i2,i3) = sqrt( (d1/ind_new(i3,6))^2);%1
                                    C(i2,i3) = sqrt( (d1/ind_new(i3,6))^2 +...
                                    ( (ind_new(i3,7) - ind_old(7)) / ind_new(i3,7) )^2 +...
                                    ( (ind_new(i3,8) - ind_old(8)) / ind_new(i3,8) )^2 );%2 3 4 5 6 7
                                case 1
                                    %C(i2,i3) = sqrt( (d1/ind_new(i3,6))^2);%1
                                    C(i2,i3) = sqrt( (d1/ind_new(i3,6))^2 +...
                                    ( (ind_new(i3,7) - ind_old(7)) / ind_new(i3,7) )^2 +...
                                    ( (ind_new(i3,8) - ind_old(8)) / ind_new(i3,8) )^2 );% to be tested + ...
                                    %( (ind_new(i3,9) - ind_old(9)) / ind_new(i3,9) )^2 );%2 3 4 5 6 7
                            end
                            
                        end
                    end

                    %--------------------------------------------------
                    % Record case in which more than one center is found
                    % within the 'D' area
                    
                    mov = length(find(C(i2,:)<inf));

                    if mov>1
                        % display and update warning
                        disp(['  Warning t+',num2str(last(j)),...
                                '; eddy: ',num2str(i2),...
                                '; ',num2str(mov),' possibilities !!!'])
                        warn_tracks(end+1,:) = [stp i2 mov];
                    end

                end % record too old
                
            end % loop on search
            
            %----------------------------------------------------------
            % 3rd: Assignment cost matrice C resolved by Munkres method
            % (Markus Buehren routine). The row index of C corresponds to
            % the old eddies and the column to the new. The result gives
            % the optimal assigment of new to old eddies in case of
            % multiple assigment possible by minimizing the cost function.
            %----------------------------------------------------------
            
            %[assign,cost] = assignmentoptimal(C);%1 2 5
            [assign,cost] = assignmentsuboptimal1(C);%3 6 4 7
            
            if cost==0 && sum(assign)~=0
                display ('Could not find solution')
                display (['Check the computation of Cost matrix ''C'' ',...
                    'with the ''assignmentoptimal.m'' routine'])
                break
            end
                
            %----------------------------------------------------------
            % 4th: update open tracks with center from current step
            for i2=1:length(search)
                
                old = assign(i2);
                
                if old~=0

                    %--------------------------------------------------
                    % add info of the new eddy center to the open 
                    % track array
                    
                    search(i2).step = [search(i2).step; stp];
                    
                    for n=2:length(search_name)
                        search(i2).(search_name{n}) =...
                            [search(i2).(search_name{n});...
                            eddy.(search_name{n})(old)];
                    end
                    
                    %--------------------------------------------------
                    % remove index of updated eddy features from array of
                    % features not updated yet
                    ind_new(old,:) = NaN;
                    
                end
            end
            
            %----------------------------------------------------------
            % 5th: remaining eddies from present step are new tracks
            % and added to open track array
            for n=2:length(search_name)
                eddy.(search_name{n}) =...
                    eddy.(search_name{n})(~isnan(ind_new(:,1)));
            end
            
            if ~isempty(eddy.type)
                for i3=1:length(eddy.type)
                    
                    search(length(search)+1).step = stp;  
                    
                    for n=2:length(search_name)
                        search(length(search)).(search_name{n}) =...
                            eddy.(search_name{n})(i3);
                    end
                end
            end
            
            % display number of new eddies
            disp([' new eddies: ',num2str(sum(~isnan(ind_new(:,1))))])

            %----------------------------------------------------------
            % 6th: eddies are considered dissipated when tracks are not
            % updated for longer than 'Dt' days; tracks are then removed
            % from open tracks array and stored in the closed track array.
            
            moved = false(1,length(search));
            
            for i2=1:length(search)
                
                % find dissipated tracks
                moved(i2) = search(i2).step(end) < stp - Dt/dps;
                
                if moved(i2)
                    % move tracks to closed tracks array
                    tracks(length(tracks)+1) = search(i2);
                end
            end
            
            % remove tracks from open track array
            search(moved) = [];
            
            % display number of old eddies
            disp([' too old eddies: ',num2str(sum(moved))])
            
            % clear some variables (re-initialized at next loop)
            clear ind_new moved
            
        end % end if first time step or not
    end % end if eddy present at that specific step
    
end % end updating eddy tracks for all step

%----------------------------------------------------------
% Add tracks that are still in the search array at the end of the
% time-series
for i=1:length(search)
    
    if i==1
        tracks(1) = search(i);
    else
        tracks(length(tracks)+1) = search(i);
    end       
    
end

%----------------------------------------------------------
% remove among tracks older than Dt + cut_off the ones
% shorter than eddy turnover time or cut_off days

short = false(1,length(tracks));

for i=1:length(tracks)
    
    if cut_off==0 && ( stepF - tracks(i).step(1) )*dps >= mean(tracks(i).tau1) + Dt
        short(i) = (tracks(i).step(end) - tracks(i).step(1) + 1)*dps < mean(tracks(i).tau1);
    elseif ( stepF - tracks(i).step(1) )*dps >= cut_off + Dt
        short(i) = (tracks(i).step(end) - tracks(i).step(1) + 1)*dps < cut_off;
    end
    
end

tracks(short) = [];
short = sum(short);

%----------------------------------------------------------
% save tracks and warnings in structure array

save([path_out,'removed_tracks',runname],'short')
save([path_out,'eddy_tracks',runname],'tracks')
save([path_out,'warnings_tracks',runname],'warn_tracks')

% close log file
diary off
