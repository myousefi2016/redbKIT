function [v_in] = Velocity(t)

Values = readtable('Flow_left_int_carotid_A_ICA_1.txt','Delimiter',','); 

t_mes = table2array(Values(:,1));
velocity = table2array(Values(:,2));

RBF_data = RBF_setup(t_mes', velocity', 'thinplate');

[v_in] = 50.0*RBF_evaluate(t, RBF_data);

end
