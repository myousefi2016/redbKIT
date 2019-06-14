function [v_in] = Velocity(t)

Values = readtable('Flow_left_middle_cerebral_artery_MCA_1.txt','Delimiter',','); 

t_mes = table2array(Values(:,1));
velocity = table2array(Values(:,2));

RBF_data = RBF_setup(t_mes', velocity', 'thinplate');

[v_in] = 50.0*RBF_evaluate(t, RBF_data);

end
